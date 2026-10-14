import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createApprovals, summary } from '../approvals.mjs';

test('ask emits the approval card and resolves with the decision', async () => {
  const a = createApprovals();
  const events = [];
  const decided = a.ask('Bash', { command: 'npm test' }, ev => events.push(ev));
  const { id } = events[0];
  assert.deepEqual(events[0], { state: 'approval', id, tool: 'Bash', summary: 'npm test' });
  assert.equal(a.size, 1);
  assert.equal(a.decide(id, true), true);
  assert.equal(await decided, true);
  assert.deepEqual(events[1], { approval: id, allowed: true });
  assert.equal(a.size, 0);
});

test('deny, unknown ids, and deciding twice', async () => {
  const a = createApprovals();
  const events = [];
  const decided = a.ask('Bash', { command: 'git push' }, ev => events.push(ev));
  assert.equal(a.decide('nope', true), false);
  assert.equal(a.decide(events[0].id, false), true);
  assert.equal(await decided, false);
  assert.equal(a.decide(events[0].id, true), false);   // already answered
  assert.deepEqual(events[1], { approval: events[0].id, allowed: false });
});

test('no answer in time is a deny', async () => {
  const a = createApprovals({ timeoutMs: 20 });
  const events = [];
  assert.equal(await a.ask('Bash', { command: 'ls' }, ev => events.push(ev)), false);
  assert.deepEqual(events[1], { approval: events[0].id, allowed: false });
  assert.equal(a.size, 0);
});

test('clear denies everything still waiting', async () => {
  const a = createApprovals();
  const p = [a.ask('Bash', { command: 'a' }, () => {}), a.ask('Bash', { command: 'b' }, () => {})];
  a.clear();
  assert.deepEqual(await Promise.all(p), [false, false]);
  assert.equal(a.size, 0);
});

test('summary: Bash command up to 80 chars, else tool + main argument', () => {
  assert.equal(summary('Bash', { command: 'npm   test\n  --watch' }), 'npm test --watch');
  const long = summary('Bash', { command: 'x'.repeat(200) });
  assert.equal(long.length, 80);
  assert.ok(long.endsWith('…'));
  assert.equal(summary('Edit', { file_path: '/w/notes.txt' }), 'Edit /w/notes.txt');
  assert.equal(summary('WebFetch', { url: 'https://example.com' }), 'WebFetch https://example.com');
  assert.equal(summary('Grep', { pattern: 'TODO' }), 'Grep TODO');
  assert.equal(summary('Task', {}), 'Task');
  assert.equal(summary('Bash'), 'Bash');
});
