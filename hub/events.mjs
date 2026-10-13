// Turns one line of Claude Code's `--output-format stream-json` into the events the watch understands.
// Returns an array (a line can carry several content blocks), possibly empty.

export function mapLine(line) {
  let e;
  try {
    e = JSON.parse(line);
  } catch {
    return [];
  }
  if (e.type === 'system' && e.subtype === 'init') return [{ state: 'thinking', session: e.session_id }];
  if (e.type === 'assistant') {
    const out = [];
    for (const c of e.message?.content ?? []) {
      if (c.type === 'tool_use') out.push({ state: 'working', tool: c.name });
      else if (c.type === 'thinking') out.push({ state: 'thinking' });
      else if (c.type === 'text' && c.text?.trim()) out.push({ state: 'speaking', text: spoken(c.text) });
    }
    return out;
  }
  if (e.type === 'result') {
    if (e.is_error || e.subtype !== 'success') return [{ state: 'error', message: 'Something went wrong on the Mac.', session: e.session_id }];
    return [{ state: 'done', session: e.session_id }];
  }
  return [];
}

// What the watch reads aloud: plain text, no markdown, one or two short sentences.
export function spoken(text) {
  const plain = text
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`([^`]*)`/g, '$1')
    .replace(/[*_#>]+/g, '')
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/\s+/g, ' ')
    .trim();
  return plain.length > 220 ? plain.slice(0, 217).replace(/\s+\S*$/, '') + '…' : plain;
}
