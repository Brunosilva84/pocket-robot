import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mapLine, spoken } from '../events.mjs';

const line = o => JSON.stringify(o);

test('init starts thinking and carries the session', () => {
  assert.deepEqual(mapLine(line({ type: 'system', subtype: 'init', session_id: 's1' })), [{ state: 'thinking', session: 's1' }]);
});

test('tool use is working, with the tool name', () => {
  const ev = mapLine(line({ type: 'assistant', message: { content: [{ type: 'tool_use', name: 'Write' }] } }));
  assert.deepEqual(ev, [{ state: 'working', tool: 'Write' }]);
});

test('assistant text becomes spoken text', () => {
  const ev = mapLine(line({ type: 'assistant', message: { content: [{ type: 'text', text: 'Created **notes.txt** for you.' }] } }));
  assert.deepEqual(ev, [{ state: 'speaking', text: 'Created notes.txt for you.' }]);
});

test('result success is done; error result is error', () => {
  assert.equal(mapLine(line({ type: 'result', subtype: 'success', is_error: false }))[0].state, 'done');
  assert.equal(mapLine(line({ type: 'result', subtype: 'error_max_turns', is_error: true }))[0].state, 'error');
});

test('noise and other events are ignored', () => {
  assert.deepEqual(mapLine('not json'), []);
  assert.deepEqual(mapLine(line({ type: 'system', subtype: 'hook_started' })), []);
});

test('spoken text drops markdown and stays short', () => {
  assert.equal(spoken('Use `npm test` and see [docs](http://x).'), 'Use npm test and see docs.');
  assert.ok(spoken('word '.repeat(100)).length <= 221);
});
