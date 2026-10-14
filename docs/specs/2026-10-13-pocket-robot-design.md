# pocket-robot — design (v1)

Talk to Claude Code on your Mac from your Apple Watch. A robot (Visor) lives on the watch and acts out what the agent is doing.

## Goal (v1, "today")

- The Visor robot runs live on the watch, with touch reactions.
- Hold the screen, speak, release: the Mac transcribes, runs Claude Code in a workspace folder, streams its state back, and the watch shows it and speaks a one-sentence reply.
- Watch and Mac on the same Wi-Fi.

Out of scope for v1 (done in v2, see 2026-10-14-pocket-robot-v2.md): approving commands from the watch, iPhone app, widgets, use away from home (Tailscale). Still out: multiple agents, custom voices.

## Parts

### 1. Watch app (`watch/`, SwiftUI, watchOS 26, watch-only)

- `Visor/` — Swift port of our `visor-core.js`: head, visor on a sphere, LED eyes as one spring-deformed shape per eye, glow, particles. Drawn with `Canvas` inside `TimelineView(.animation)`. Owns all character state; the UI only sets an expression and forwards gestures.
- Gestures on the robot:
  - tap → poke (annoyed); 3 within 1.7 s → dizzy + visor double roll
  - drag across it → pet (love, hearts)
  - finger position while touching → head looks toward it
  - Digital Crown spun fast → dizzy
  - long press (0.35 s) → talk: record while held, send on release; dragging off the robot cancels
- Agent states → expressions:

  | Agent state | Expression |
  | --- | --- |
  | idle | neutral |
  | listening (while recording) | surprised (open eyes, cyan) |
  | thinking | thinking |
  | working | working (dots in the eyes) |
  | speaking | happy, eyes bounce while the reply is spoken |
  | done | success (stars, sparks, roll) |
  | error | angry |
  | offline (hub unreachable) | sleepy |

- Reply: last reply shown as text under the robot; spoken with `AVSpeechSynthesizer`.
- Config: hub URL + token compiled in from a generated, git-ignored `Config.swift` written by `scripts/configure`.
- Permissions: microphone (`NSMicrophoneUsageDescription`); local network HTTP allowed (`NSAllowsLocalNetworking`).
- Project generated with XcodeGen (`watch/project.yml`).

### 2. Hub (`hub/`, Node, runs on the Mac)

- `POST /talk` — body: recorded audio (m4a), header `Authorization: Bearer <token>`. Response: NDJSON stream of events until the turn ends:
  - `{"state":"thinking"}`, `{"state":"working","tool":"Edit"}`, `{"state":"speaking","text":"…"}`, `{"state":"done"}`, `{"state":"error","message":"…"}`; first event `{"heard":"<transcript>"}`.
- `GET /health` — `{"ok":true}` (token required), used by the watch to show online/offline.
- Transcription: `whisperkit-cli transcribe --audio-path <file> --model <small model>`.
- Agent: `claude -p <transcript> --output-format stream-json --verbose --resume <session> --append-system-prompt <short spoken reply rule> --permission-mode acceptEdits --allowedTools <safe list>` with `cwd = ~/pocket-robot-workspace`. Stream events map to states: tool_use → working (+ tool name); assistant text → speaking; result → done; non-zero exit / error result → error.
- Session id saved in `~/.pocket-robot/state.json` so the conversation continues across turns.
- Token and port in `~/.pocket-robot/config.json` (mode 0600), created by `scripts/configure`; never logged.

### 3. Scripts

- `scripts/configure` — creates the token and config, finds the Mac's LAN IP, writes `watch/PocketRobot/Config.swift`.
- `scripts/hub` — runs the hub in the foreground.

## Error handling

- Hub unreachable / token rejected → watch shows offline (sleepy) and a short message; retries `/health` every 10 s.
- Transcription empty → `{"state":"error","message":"I didn't catch that"}`.
- Claude Code not signed in or exits non-zero → error state with a short message; details only in the hub log.
- A new `/talk` while a turn runs → 409; the watch says it's busy.

## Testing

- Hub: `node --test` for the stream-json → state mapping (fixture lines) and auth.
- Watch: builds for the watchOS Simulator; robot states checked by rendering each expression in the Simulator; end-to-end on the real watch against the running hub.

## Repo

`github.com/<user>/pocket-robot`. Code MIT; the Visor character is all rights reserved (see LICENSE). `Config.swift`, `~/.pocket-robot/` and build output are never committed.
