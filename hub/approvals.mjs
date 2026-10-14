// Pending permission requests: Claude Code asks (through hub/approver.mjs), the watch or phone answers with /approve.
// No answer within the timeout means deny.

import { randomUUID } from 'node:crypto';

export function createApprovals({ timeoutMs = 60_000 } = {}) {
  const pending = new Map();   // id -> finish(allowed)
  return {
    // Emits the approval event, then resolves to true/false once decided (or timed out).
    ask(tool, input, emit) {
      const id = randomUUID();
      return new Promise(resolve => {
        const finish = allowed => {
          clearTimeout(timer);
          pending.delete(id);
          emit({ approval: id, allowed });
          resolve(allowed);
        };
        const timer = setTimeout(() => finish(false), timeoutMs);
        pending.set(id, finish);
        emit({ state: 'approval', id, tool, summary: summary(tool, input) });
      });
    },
    // false if there is no such pending approval
    decide(id, allow) {
      const finish = pending.get(id);
      if (!finish) return false;
      finish(allow === true);
      return true;
    },
    // deny everything still waiting (the turn ended)
    clear() {
      for (const finish of [...pending.values()]) finish(false);
    },
    get size() { return pending.size; },
  };
}

// What the watch shows: the command for Bash, otherwise the tool plus its main argument.
export function summary(tool, input = {}) {
  const arg = tool === 'Bash' ? input.command : (input.file_path ?? input.url ?? input.pattern);
  const text = (tool === 'Bash' ? String(arg ?? '') : [tool, arg].filter(Boolean).join(' ')).replace(/\s+/g, ' ').trim();
  return text.length > 80 ? text.slice(0, 79) + '…' : text || tool;
}
