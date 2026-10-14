// Tiny stdio MCP server that Claude Code calls for permission prompts (`--permission-prompt-tool mcp__pocket__approve`).
// Each request is forwarded to the hub on 127.0.0.1, which asks the watch or phone and waits for Approve / Deny.
//
// Env: POCKET_ROBOT_HOME (token in config.json), POCKET_ROBOT_PORT (the hub's port).

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const HOME = process.env.POCKET_ROBOT_HOME ?? join(homedir(), '.pocket-robot');
const PORT = process.env.POCKET_ROBOT_PORT;

const TOOL = {
  name: 'approve',
  description: 'Asks the user on their watch or phone whether a tool call may run.',
  inputSchema: {
    type: 'object',
    properties: { tool_name: { type: 'string' }, input: { type: 'object' }, tool_use_id: { type: 'string' } },
    required: ['tool_name', 'input'],
  },
};

// Claude Code expects the decision as JSON text: allow (with the input to run) or deny (with a reason).
async function approve({ tool_name, input = {}, tool_use_id }) {
  let r;
  try {
    const { token } = JSON.parse(readFileSync(join(HOME, 'config.json'), 'utf8'));
    const res = await fetch(`http://127.0.0.1:${PORT}/approval`, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ tool_name, input, tool_use_id }),
    });
    r = res.ok ? await res.json() : { allow: false, message: `The hub refused the approval request (${res.status}).` };
  } catch {
    r = { allow: false, message: 'Could not reach the hub to ask for approval.' };
  }
  return r.allow
    ? { behavior: 'allow', updatedInput: input }
    : { behavior: 'deny', message: r.message ?? 'The user denied this.' };
}

async function handle(msg) {
  switch (msg.method) {
    case 'initialize':
      return {
        protocolVersion: msg.params?.protocolVersion ?? '2025-06-18',
        capabilities: { tools: {} },
        serverInfo: { name: 'pocket', version: '2.0.0' },
      };
    case 'ping': return {};
    case 'tools/list': return { tools: [TOOL] };
    case 'tools/call': {
      if (msg.params?.name !== 'approve') throw { code: -32602, message: `Unknown tool: ${msg.params?.name}` };
      const decision = await approve(msg.params.arguments ?? {});
      return { content: [{ type: 'text', text: JSON.stringify(decision) }] };
    }
    default: throw { code: -32601, message: `Method not found: ${msg.method}` };
  }
}

const reply = o => process.stdout.write(JSON.stringify({ jsonrpc: '2.0', ...o }) + '\n');

let buf = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', d => {
  buf += d;
  let i;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
    if (!line) continue;
    let msg;
    try { msg = JSON.parse(line); } catch { reply({ id: null, error: { code: -32700, message: 'Parse error' } }); continue; }
    if (msg.id === undefined) continue;   // notifications (notifications/initialized, cancelled, …) need no answer
    handle(msg).then(result => reply({ id: msg.id, result }),
      e => reply({ id: msg.id, error: { code: e.code ?? -32603, message: e.message ?? String(e) } }));
  }
});
