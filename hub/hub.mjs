// pocket-robot hub: receives what you said on the watch or phone, runs Claude Code on the Mac, streams its state back.
//
//   GET  /health   -> {"ok":true,"busy":false,"version":2}
//   POST /talk     -> body: audio (m4a) or text/plain; response: NDJSON events until the turn ends
//   POST /approve  -> {"id","allow"}: answers a pending approval (404 if none)
//   GET  /history  -> {"turns":[{at,heard,reply,ok}]}, newest last, max 50
//   POST /new      -> forgets the Claude session
//   POST /approval -> internal, from hub/approver.mjs on 127.0.0.1 only
//
// All need `Authorization: Bearer <token>` (token in ~/.pocket-robot/config.json).
// Env: POCKET_ROBOT_HOME (default ~/.pocket-robot), POCKET_ROBOT_PORT, POCKET_ROBOT_CLAUDE (claude binary).

import { createServer } from 'node:http';
import { spawn, execFile } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, unlinkSync, existsSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { timingSafeEqual, randomUUID } from 'node:crypto';
import { mapLine } from './events.mjs';
import { createApprovals } from './approvals.mjs';

const HOME = process.env.POCKET_ROBOT_HOME ?? join(homedir(), '.pocket-robot');
const CONFIG = join(HOME, 'config.json');
const STATE = join(HOME, 'state.json');
const HISTORY = join(HOME, 'history.json');
const MODELS = join(HOME, 'models');
const APPROVER = fileURLToPath(new URL('./approver.mjs', import.meta.url));
const CLAUDE = process.env.POCKET_ROBOT_CLAUDE ?? 'claude';

if (!existsSync(CONFIG)) {
  console.error('No config. Run scripts/configure first.');
  process.exit(1);
}
const config = JSON.parse(readFileSync(CONFIG, 'utf8'));
const PORT = Number(process.env.POCKET_ROBOT_PORT ?? config.port ?? 8787);
const WORKSPACE = config.workspace ?? join(homedir(), 'pocket-robot-workspace');
const MODEL = config.model ?? 'small';
// Read and edit files in the workspace without asking; everything else (Bash, …) waits for an approval.
const TOOLS = config.allowedTools ?? 'Read,Write,Edit,Glob,Grep,WebSearch,WebFetch';

let busy = false;
let turn = null;          // the running /talk: { send, last }
const approvals = createApprovals();
const seen = new Set();   // addresses that already passed /health (logged once)

const readJSON = (file, fallback) => (existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : fallback);
const writeJSON = (file, o) => writeFileSync(file, JSON.stringify(o, null, 2), { mode: 0o600 });
const loadState = () => readJSON(STATE, {});
const saveState = s => writeJSON(STATE, s);

function remember(t) {
  const turns = readJSON(HISTORY, { turns: [] }).turns;
  turns.push(t);
  writeJSON(HISTORY, { turns: turns.slice(-50) });
}

function authorized(req) {
  const got = Buffer.from((req.headers.authorization ?? '').replace(/^Bearer /, ''));
  const want = Buffer.from(config.token);
  return got.length === want.length && timingSafeEqual(got, want);
}

const loopback = req => ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress);

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

const readJSONBody = async req => { try { return JSON.parse(await readBody(req, 1024 * 1024)); } catch { return null; } };

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

function runClaude(prompt, session, t) {
  return new Promise(resolve => {
    // the approver reads the token from POCKET_ROBOT_HOME, so it never shows up in the process list
    const mcp = { mcpServers: { pocket: { type: 'stdio', command: process.execPath, args: [APPROVER],
      env: { POCKET_ROBOT_HOME: HOME, POCKET_ROBOT_PORT: String(server.address().port) } } } };
    const args = ['-p', prompt, '--output-format', 'stream-json', '--verbose',
      '--setting-sources', 'project,local', '--permission-mode', 'acceptEdits', '--allowedTools', TOOLS,
      '--mcp-config', JSON.stringify(mcp), '--permission-prompt-tool', 'mcp__pocket__approve'];
    if (session) args.push('--resume', session);
    const child = spawn(CLAUDE, args, { cwd: WORKSPACE, stdio: ['ignore', 'pipe', 'pipe'] });
    let buf = '', newSession = session, lastText = '';
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
          if (key !== t.last) { t.send(ev); t.last = key; }
        }
      }
    });
    child.stderr.on('data', d => log('claude:', String(d).trim().slice(0, 300)));
    child.on('error', err => log('claude failed to start:', err.message));
    child.on('close', code => {
      if (code !== 0 && t.last !== 'error') t.send({ state: 'error', message: 'Claude Code stopped with an error.' });
      resolve({ session: newSession, text: lastText, ok: code === 0 });
    });
  });
}

const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);
const json = (res, status, o) => res.writeHead(status, { 'content-type': 'application/json' }).end(JSON.stringify(o));

async function talk(req, res) {
  if (busy) { res.writeHead(409).end(); return; }
  busy = true;
  const typed = (req.headers['content-type'] ?? '').startsWith('text/plain');
  const audio = join(tmpdir(), `pocket-robot-${randomUUID()}.m4a`);
  res.writeHead(200, { 'content-type': 'application/x-ndjson', 'cache-control': 'no-cache' });
  const send = ev => { if (!res.writableEnded) res.write(JSON.stringify(ev) + '\n'); };
  turn = { send, last: null };
  try {
    const body = await readBody(req);
    send({ state: 'thinking' });
    let heard;
    if (typed) heard = body.toString('utf8').trim();
    else { writeFileSync(audio, body); heard = await transcribe(audio); }
    log('heard:', JSON.stringify(heard));
    if (!heard) { send({ state: 'error', message: "I didn't catch that." }); return; }
    send({ heard });
    const r = await runClaude(heard, loadState().session, turn);
    if (r.session) saveState({ ...loadState(), session: r.session });
    remember({ at: new Date().toISOString(), heard, reply: r.text, ok: r.ok });
    if (r.ok) {
      if (r.text) send({ state: 'speaking', text: r.text });
      send({ state: 'done' });
      log('reply:', JSON.stringify(r.text));
    }
  } catch (err) {
    log('talk failed:', err.message);
    send({ state: 'error', message: 'Something went wrong on the Mac.' });
  } finally {
    approvals.clear();
    turn = null;
    busy = false;
    res.end();
    try { unlinkSync(audio); } catch {}
  }
}

const server = createServer(async (req, res) => {
  if (!authorized(req)) { res.writeHead(401).end(); log(req.method, req.url, '401'); return; }
  const route = `${req.method} ${req.url}`;

  if (route === 'GET /health') {
    const who = req.socket.remoteAddress;
    if (!seen.has(who)) { seen.add(who); log('client connected from', who); }
    return json(res, 200, { ok: true, busy, version: 2 });
  }

  if (route === 'POST /talk') return talk(req, res);

  if (route === 'POST /approve') {
    const b = await readJSONBody(req);
    if (!b?.id) return json(res, 400, { error: 'id required' });
    const found = approvals.decide(b.id, b.allow === true);
    if (found) log('approval', b.allow === true ? 'allowed' : 'denied');
    return found ? json(res, 200, { ok: true }) : json(res, 404, { error: 'no such approval' });
  }

  if (route === 'GET /history') return json(res, 200, { turns: readJSON(HISTORY, { turns: [] }).turns });

  if (route === 'POST /new') {
    const { session, ...rest } = loadState();
    saveState(rest);
    log('new conversation');
    return json(res, 200, { ok: true });
  }

  // From the approver (started by Claude Code): ask on the open /talk stream and wait for the decision.
  if (route === 'POST /approval') {
    if (!loopback(req)) { res.writeHead(403).end(); return; }
    const b = await readJSONBody(req);
    if (!b?.tool_name) return json(res, 400, { error: 'tool_name required' });
    if (!turn) return json(res, 200, { allow: false, message: 'Nobody is there to approve this.' });
    const t = turn;
    log('approval asked:', b.tool_name);
    const allow = await approvals.ask(b.tool_name, b.input, t.send);
    t.last = null;   // after the approval card, show the next state even if it repeats
    return json(res, 200, allow ? { allow } : { allow, message: 'The user denied this (or did not answer in time).' });
  }

  res.writeHead(404).end();
});

mkdirSync(HOME, { recursive: true });
mkdirSync(WORKSPACE, { recursive: true });
server.listen(PORT, '0.0.0.0', () => log(`pocket-robot hub on :${server.address().port}, workspace ${WORKSPACE}`));
