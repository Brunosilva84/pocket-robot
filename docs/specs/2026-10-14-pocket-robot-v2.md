# pocket-robot — design (v2)

v2 adds what v1 left out: an iPhone app, approving commands from the watch or phone, use away from home, and a watch complication.

## Goals

1. **iPhone app** (companion; it carries the watch app, so installing on the phone over USB also installs the watch app).
   - Same Visor robot, hold-to-talk with the phone mic, or type a message.
   - History of turns (what you said, what the robot answered).
   - Settings: hub URL + token (Keychain), "Test connection", "New conversation". Settings are sent to the watch, so changing the Mac's address never needs a rebuild.
   - Relay: when the watch can't reach the hub directly but the phone is nearby, the watch talks through the phone.
2. **Approvals**: Claude Code may run shell commands and other gated tools, but each one waits for Approve / Deny on the watch or phone. No answer in 60 s → denied.
3. **Away from home**: works over Tailscale (MagicDNS name `*.ts.net`), documented in the README.
4. **Watch complication**: the robot's face on the watch face; tapping opens the app.

## Hub API (v2)

Every request needs `Authorization: Bearer <token>`.

| Method | Path | Body | Response |
| --- | --- | --- | --- |
| GET | `/health` | — | `{"ok":true,"busy":false,"version":2}` |
| POST | `/talk` | `audio/*` (m4a) **or** `text/plain` (typed prompt, no transcription) | NDJSON stream (below) |
| POST | `/approve` | `{"id":"…","allow":true}` | 200, or 404 if no such pending approval |
| GET | `/history` | — | `{"turns":[{"at":"ISO","heard":"…","reply":"…","ok":true}]}` newest last, max 50 |
| POST | `/new` | — | 200; forgets the Claude session (next turn starts a new conversation) |

Stream events (one JSON object per line), v1 plus:

- `{"heard":"…"}` — transcript (or the typed text)
- `{"state":"thinking"}` · `{"state":"working","tool":"Edit"}`
- `{"state":"approval","id":"<uuid>","tool":"Bash","summary":"npm test"}` — waiting for `/approve`
- `{"approval":"<uuid>","allowed":true}` — decision made (by any client, or timeout → false)
- `{"state":"speaking","text":"…"}` · `{"state":"done"}` · `{"state":"error","message":"…"}`

### Approvals inside the hub

- `claude -p` runs with `--permission-prompt-tool mcp__pocket__approve` and `--mcp-config` pointing at a tiny stdio MCP server (`hub/approver.mjs`).
- The approver forwards each permission request to the hub on `127.0.0.1` (same token); the hub emits the `approval` event on the open `/talk` stream and waits for `/approve` (60 s timeout → deny).
- `allowedTools` (no prompt) stays the safe list: `Read,Write,Edit,Glob,Grep,WebSearch,WebFetch`. Everything else (Bash, …) goes through the prompt.
- Summary: for Bash the command (≤ 80 chars); otherwise the tool name plus the main argument.

## Apple project (`apple/`, XcodeGen)

```
apple/
  project.yml
  Shared/      Visor/ (robot), HubClient, HubEvent, Settings, Config.swift (generated, ignored)
  iOS/         iPhone app
  Watch/       watch app (was watch/PocketRobot)
  WatchWidget/ complication (WidgetKit)
```

- iOS bundle `co.brsilva.pocketrobot`; watch `co.brsilva.pocketrobot.watchkitapp` (`WKCompanionAppBundleIdentifier`, `WKRunsIndependentlyOfCompanionApp: true`); widget `co.brsilva.pocketrobot.watchkitapp.widget`.
- iOS 26, watchOS 26, Swift 6 strict concurrency.
- Settings: `Config.swift` gives defaults; the phone stores overrides (URL in UserDefaults, token in Keychain) and pushes both to the watch with `WCSession.updateApplicationContext`; the watch stores them and uses them over `Config`.
- ATS: `NSAllowsLocalNetworking` plus an exception for `ts.net` (HTTP over Tailscale's encrypted tunnel).

### WatchConnectivity relay

- Watch → phone: `["talk": Data(audio m4a)]` or `["approve": id, "allow": Bool]` via `sendMessage`.
- Phone → watch: each hub event as `["event": Data(json line)]`, and `["end": true]` when the stream ends; `["error": "unreachable"|"unauthorized"|"busy"]` on failure.
- The watch tries the hub directly first; on unreachable and `WCSession.isReachable`, it sends through the phone.

## Testing

- Hub: `npm test` — events mapping, approvals (pending/resolve/timeout), text `/talk`, history, `/new`.
- Apple: builds for iOS + watchOS simulators and for devices (team set by `POCKET_ROBOT_TEAM`); screenshots of the iPhone app in `docs/screens/`.
