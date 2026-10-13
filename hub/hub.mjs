// pocket-robot hub: receives what you said on the watch, runs Claude Code on the Mac, streams its state back.
//
//   GET  /health  -> {"ok":true}
//   POST /talk    -> body: audio (m4a); response: NDJSON events until the turn ends
//
// Both need `Authorization: Bearer <token>` (token in ~/.pocket-robot/config.json).

import { createServer } from 'node:http';
import { spawn, execFile } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, unlinkSync, existsSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { timingSafeEqual, randomUUID } from 'node:crypto';
import { mapLine } from './events.mjs';

const HOME = join(homedir(), '.pocket-robot');
const CONFIG = join(HOME, 'config.json');
const STATE = join(HOME, 'state.json');
const MODELS = join(HOME, 'models');

if (!existsSync(CONFIG)) {
  console.error('No config. Run scripts/configure first.');
  process.exit(1);
}
const config = JSON.parse(readFileSync(CONFIG, 'utf8'));
const PORT = config.port ?? 8787;
const WORKSPACE = config.workspace ?? join(homedir(), 'pocket-robot-workspace');
const MODEL = config.model ?? 'small';
// Read and edit files in the workspace; no shell until approvals exist on the watch.
const TOOLS = config.allowedTools ?? 'Read,Write,Edit,Glob,Grep,WebSearch,WebFetch';

let busy = false;
const seen = new Set();   // addresses that already passed /health (logged once)

const loadState = () => (existsSync(STATE) ? JSON.parse(readFileSync(STATE, 'utf8')) : {});
const saveState = s => writeFileSync(STATE, JSON.stringify(s, null, 2), { mode: 0o600 });

function authorized(req) {
  const got = Buffer.from((req.headers.authorization ?? '').replace(/^Bearer /, ''));
  const want = Buffer.from(config.token);
  return got.length === want.length && timingSafeEqual(got, want);
}

function readBody(req, limit = 20 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', c => {
      size += c.length;
      if (size > limit) { reject(new Error('too large')); req.destroy(); }
      else chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

function transcribe(file) {
  return new Promise(resolve => {
    execFile('whisperkit-cli', ['transcribe', '--audio-path', file, '--model', MODEL,
      '--download-model-path', MODELS, '--download-tokenizer-path', MODELS],
      { timeout: 120_000 }, (err, stdout) => {
        if (err) { log('transcribe failed:', err.message); return resolve(''); }
        // the transcript is the last non-empty line
        const lines = stdout.split('\n').map(l => l.trim()).filter(Boolean);
        resolve((lines.at(-1) ?? '').replace(/^\[.*?\]\s*/, ''));
      });
  });
}

function runClaude(prompt, session, send) {
  return new Promise(resolve => {
    const args = ['-p', prompt, '--output-format', 'stream-json', '--verbose',
      '--setting-sources', 'project,local', '--permission-mode', 'acceptEdits', '--allowedTools', TOOLS];
    if (session) args.push('--resume', session);
    const child = spawn('claude', args, { cwd: WORKSPACE, stdio: ['ignore', 'pipe', 'pipe'] });
    let buf = '', last = null, newSession = session, lastText = '';
    child.stdout.on('data', d => {
      buf += d;
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i); buf = buf.slice(i + 1);
        for (const ev of mapLine(line)) {
          if (ev.session) { newSession = ev.session; delete ev.session; }
          if (ev.state === 'speaking') { lastText = ev.text; continue; }   // only the final text is spoken
          if (ev.state === 'done') continue;                                // sent once, after the reply
          const key = ev.state + (ev.tool ?? '');
          if (key !== last) { send(ev); last = key; }
        }
      }
    });
    child.stderr.on('data', d => log('claude:', String(d).trim().slice(0, 300)));
    child.on('close', code => {
      if (code !== 0 && last !== 'error') send({ state: 'error', message: 'Claude Code stopped with an error.' });
      resolve({ session: newSession, text: lastText, ok: code === 0 });
    });
  });
}

const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

const server = createServer(async (req, res) => {
  if (!authorized(req)) { res.writeHead(401).end(); log(req.method, req.url, '401'); return; }

  if (req.method === 'GET' && req.url === '/health') {
    const who = req.socket.remoteAddress;
    if (!seen.has(who)) { seen.add(who); log('watch connected from', who); }
    res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ ok: true, busy }));
    return;
  }

  if (req.method === 'POST' && req.url === '/talk') {
    if (busy) { res.writeHead(409).end(); return; }
    busy = true;
    const audio = join(tmpdir(), `pocket-robot-${randomUUID()}.m4a`);
    res.writeHead(200, { 'content-type': 'application/x-ndjson', 'cache-control': 'no-cache' });
    const send = ev => res.write(JSON.stringify(ev) + '\n');
    try {
      writeFileSync(audio, await readBody(req));
      send({ state: 'thinking' });
      const heard = await transcribe(audio);
      log('heard:', JSON.stringify(heard));
      if (!heard) { send({ state: 'error', message: "I didn't catch that." }); return; }
      send({ heard });
      const state = loadState();
      const r = await runClaude(heard, state.session, send);
      if (r.session) saveState({ ...state, session: r.session });
      if (r.ok) {
        if (r.text) send({ state: 'speaking', text: r.text });
        send({ state: 'done' });
        log('reply:', JSON.stringify(r.text));
      }
    } catch (err) {
      log('talk failed:', err.message);
      send({ state: 'error', message: 'Something went wrong on the Mac.' });
    } finally {
      busy = false;
      res.end();
      try { unlinkSync(audio); } catch {}
    }
    return;
  }

  res.writeHead(404).end();
});

mkdirSync(HOME, { recursive: true });
mkdirSync(WORKSPACE, { recursive: true });
server.listen(PORT, '0.0.0.0', () => log(`pocket-robot hub on :${PORT}, workspace ${WORKSPACE}`));
