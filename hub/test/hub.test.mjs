// Runs a real hub on a free port with a temp home and a fake `claude` (test/fake-claude.mjs).

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, statSync, rmSync } from 'node:fs';
import { tmpdir, networkInterfaces } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = p => fileURLToPath(new URL(p, import.meta.url));
const TOKEN = 'test-token';
let home, hub, base;

before(async () => {
  home = mkdtempSync(join(tmpdir(), 'pocket-robot-test-'));
  writeFileSync(join(home, 'config.json'), JSON.stringify({ token: TOKEN, workspace: join(home, 'workspace') }));
  hub = spawn(process.execPath, [here('../hub.mjs')], {
    env: { ...process.env, POCKET_ROBOT_HOME: home, POCKET_ROBOT_PORT: '0', POCKET_ROBOT_CLAUDE: here('./fake-claude.mjs') },
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  const port = await new Promise((resolve, reject) => {
    let out = '';
    hub.stdout.on('data', d => { out += d; const m = out.match(/hub on :(\d+)/); if (m) resolve(m[1]); });
    hub.on('exit', code => reject(new Error(`hub exited ${code}`)));
  });
  base = `http://127.0.0.1:${port}`;
});

after(() => { hub.kill(); rmSync(home, { recursive: true, force: true }); });

const call = (path, { token = TOKEN, ...init } = {}) =>
  fetch(base + path, { ...init, headers: { authorization: `Bearer ${token}`, ...init.headers } });

// Sends a typed prompt and collects the NDJSON events; `onEvent` may answer approvals.
async function talk(text, onEvent = () => {}) {
  const res = await call('/talk', { method: 'POST', headers: { 'content-type': 'text/plain' }, body: text });
  assert.equal(res.status, 200);
  const events = [];
  let buf = '';
  for await (const chunk of res.body) {
    buf += Buffer.from(chunk).toString();
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const ev = JSON.parse(buf.slice(0, i)); buf = buf.slice(i + 1);
      events.push(ev);
      await onEvent(ev);
    }
  }
  return events;
}

const approve = (id, allow) => call('/approve', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ id, allow }) });

test('every endpoint needs the token', async () => {
  for (const [method, path] of [['GET', '/health'], ['POST', '/talk'], ['POST', '/approve'], ['GET', '/history'], ['POST', '/new'], ['POST', '/approval']]) {
    assert.equal((await call(path, { method, token: 'wrong' })).status, 401, `${method} ${path}`);
  }
});

test('health reports version 2', async () => {
  assert.deepEqual(await (await call('/health')).json(), { ok: true, busy: false, version: 2 });
});

test('text /talk skips transcription and streams the turn', async () => {
  const events = await talk('hello robot');
  assert.deepEqual(events, [
    { state: 'thinking' },
    { heard: 'hello robot' },
    { state: 'thinking' },   // Claude Code started (as in v1)
    { state: 'speaking', text: 'heard hello robot, resumed none' },
    { state: 'done' },
  ]);
});

test('the next turn resumes the session; /new forgets it', async () => {
  assert.equal((await talk('again')).at(-2).text, 'heard again, resumed fake-session-1');
  assert.equal((await call('/new', { method: 'POST' })).status, 200);
  assert.equal(JSON.parse(readFileSync(join(home, 'state.json'), 'utf8')).session, undefined);
  assert.equal((await talk('fresh')).at(-2).text, 'heard fresh, resumed none');
});

test('approval allowed: card, decision, then the tool runs', async () => {
  const events = await talk('use the shell', async ev => {
    if (ev.state === 'approval') assert.equal((await approve(ev.id, true)).status, 200);
  });
  const card = events.find(e => e.state === 'approval');
  assert.deepEqual(card, { state: 'approval', id: card.id, tool: 'Bash', summary: 'ls -la' });
  assert.deepEqual(events.find(e => 'approval' in e), { approval: card.id, allowed: true });
  assert.match(events.at(-2).text, /^allow ls -la heard use the shell/);
  assert.equal(events.at(-1).state, 'done');
});

test('approval denied reaches Claude Code as a deny', async () => {
  const events = await talk('use the shell', async ev => {
    if (ev.state === 'approval') await approve(ev.id, false);
  });
  assert.equal(events.find(e => 'approval' in e).allowed, false);
  assert.match(events.at(-2).text, /^deny heard use the shell/);
});

test('/approve for an unknown id is 404', async () => {
  assert.equal((await approve('nope', true)).status, 404);
});

test('history keeps the turns, newest last, in a private file', async () => {
  const { turns } = await (await call('/history')).json();
  assert.deepEqual(turns.map(t => t.heard), ['hello robot', 'again', 'fresh', 'use the shell', 'use the shell']);
  assert.equal(turns[0].reply, 'heard hello robot, resumed none');
  assert.ok(turns.every(t => t.ok && !Number.isNaN(Date.parse(t.at))));
  assert.equal(statSync(join(home, 'history.json')).mode & 0o777, 0o600);
});

test('history keeps at most 50 turns', async () => {
  const old = Array.from({ length: 60 }, (_, i) => ({ at: new Date().toISOString(), heard: `old ${i}`, reply: '', ok: true }));
  writeFileSync(join(home, 'history.json'), JSON.stringify({ turns: old }));
  await talk('latest');
  const { turns } = await (await call('/history')).json();
  assert.equal(turns.length, 50);
  assert.equal(turns[0].heard, 'old 11');
  assert.equal(turns.at(-1).heard, 'latest');
});

test('/approval is refused from anything but loopback', async t => {
  const lan = Object.values(networkInterfaces()).flat().find(i => i.family === 'IPv4' && !i.internal)?.address;
  if (!lan) return t.skip('no LAN address');
  const res = await fetch(base.replace('127.0.0.1', lan) + '/approval', {
    method: 'POST', headers: { authorization: `Bearer ${TOKEN}` }, body: JSON.stringify({ tool_name: 'Bash', input: {} }),
  });
  assert.equal(res.status, 403);
});
