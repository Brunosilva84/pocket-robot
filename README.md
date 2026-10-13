# Pocket Robot

Talk to Claude Code on your Mac from your Apple Watch. A little robot lives on your wrist and acts out what the agent is doing: listening, thinking, working, talking, done.

Hold the screen, say what you want, let go. Your Mac transcribes it, Claude Code does the work in a folder you choose, and the robot tells you what happened, out loud.

## How it works

```
Apple Watch (SwiftUI)  ──audio──▶  Hub on your Mac (Node)  ──▶  whisperkit-cli (speech to text, on device)
        ▲                                   │
        └──── live state + reply ◀──────────┴──────────▶  Claude Code (headless, in your workspace folder)
```

- **Watch app** (`watch/`): the Visor robot, drawn in code with SwiftUI `Canvas` — springs, not sprites. Tap it, pet it, spin the Digital Crown. Hold to talk.
- **Hub** (`hub/`): a small Node server. It transcribes on your Mac, runs `claude -p` with streaming output, and turns each step into a state the robot acts out.

| Agent | Robot |
| --- | --- |
| listening | eyes wide open |
| thinking | eyes glance around |
| working | loading dots in its eyes |
| speaking | happy, eyes bounce as it talks |
| done | star eyes, sparks, a visor roll |
| error | angry |
| offline | asleep |

## Requirements

- Mac with Apple silicon, Xcode 26, Node 20+
- Apple Watch on watchOS 26 (a free Apple ID can sign the app)
- [Claude Code](https://claude.com/claude-code), signed in
- `brew install xcodegen whisperkit-cli`
- Watch and Mac on the same Wi-Fi

## Setup

```bash
scripts/configure      # creates ~/.pocket-robot/config.json (token) and the watch's Config.swift
scripts/hub            # starts the hub (keep it running)
```

Then build the watch app:

```bash
cd watch && xcodegen generate && open PocketRobot.xcodeproj
```

Pick your team under Signing & Capabilities, choose your Apple Watch as the destination, and Run.

The first transcription downloads the speech model (~250 MB) to `~/.pocket-robot/models`.

## Safety

- Every request needs the token from `~/.pocket-robot/config.json`. It is never committed (`Config.swift` is git-ignored).
- Claude Code runs only in your workspace folder (`~/pocket-robot-workspace` by default) and can read and edit files and search the web there. Shell commands are off until the watch can approve them.

## Roadmap

- Approve or deny commands from the watch
- Use it away from home
- More robots, an iPhone app, widgets

## License

MIT
