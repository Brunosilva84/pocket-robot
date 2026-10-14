#!/usr/bin/env node
// Stands in for `claude -p … --output-format stream-json` in the hub tests.
// A prompt containing "shell" asks for a Bash approval through the real approver (from --mcp-config) first.
// The reply says what happened: "allow"/"deny", the prompt, and the resumed session.

import { spawn } from 'node:child_process';

const args = process.argv.slice(2);
const opt = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
const prompt = opt('-p');
const resumed = opt('--resume') ?? 'none';
const out = o => process.stdout.write(JSON.stringify(o) + '\n');

// One MCP round trip: initialize, then tools/call approve.
function askApprover(config) {
  const { command, args, env } = JSON.parse(config).mcpServers.pocket;
  const child = spawn(command, args, { env: { ...process.env, ...env }, stdio: ['pipe', 'pipe', 'inherit'] });
  const send = o => child.stdin.write(JSON.stringify({ jsonrpc: '2.0', ...o }) + '\n');
  return new Promise(resolve => {
    let buf = '';
    child.stdout.on('data', d => {
      buf += d;
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const msg = JSON.parse(buf.slice(0, i)); buf = buf.slice(i + 1);
        if (msg.id === 1) {
          send({ method: 'notifications/initialized' });
          send({ id: 2, method: 'tools/call', params: { name: 'approve',
            arguments: { tool_name: 'Bash', input: { command: 'ls -la' }, tool_use_id: 'toolu_1' } } });
        } else if (msg.id === 2) {
          child.kill();
          resolve(JSON.parse(msg.result.content[0].text));
        }
      }
    });
    send({ id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'fake', version: '0' } } });
  });
}

const session = resumed === 'none' ? 'fake-session-1' : resumed;
out({ type: 'system', subtype: 'init', session_id: session });
let decision = '';
if (prompt.includes('shell')) {
  out({ type: 'assistant', message: { content: [{ type: 'tool_use', name: 'Bash', input: { command: 'ls -la' } }] } });
  const d = await askApprover(opt('--mcp-config'));
  decision = d.behavior + (d.updatedInput ? ` ${d.updatedInput.command}` : '') + ' ';
}
out({ type: 'assistant', message: { content: [{ type: 'text', text: `${decision}heard ${prompt}, resumed ${resumed}` }] } });
out({ type: 'result', subtype: 'success', is_error: false, session_id: session });
