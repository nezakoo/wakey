# Wakey

[![CI](https://github.com/nezakoo/wakey/actions/workflows/ci.yml/badge.svg)](https://github.com/nezakoo/wakey/actions/workflows/ci.yml)

A macOS menu-bar app that keeps the Mac awake while your AI coding agents work, then lets it sleep
once they are done. It also keeps it awake while any process runs, for a set time, until a clock
time, or with the lid closed.

## Install

Needs macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`). Wakey is built from
source on your Mac, so there is no unsigned download for Gatekeeper to block.

    curl -fsSL https://raw.githubusercontent.com/nezakoo/wakey/main/install.sh | bash

This builds the latest release. Run it again to update; Wakey menu → Check for updates… tells you
when there is a new one. Or with Homebrew:

    brew tap nezakoo/wakey https://github.com/nezakoo/wakey
    brew install nezakoo/wakey/wakey

Or from a clone: `./build.sh && cp -R build/Wakey.app /Applications/ && open /Applications/Wakey.app`.

Then Wakey menu → Open at login.

Uninstall: Quit Wakey, then `rm -rf /Applications/Wakey.app ~/.local/state/wakey`
(and `sudo rm /etc/sudoers.d/wakey` if you set up closed-lid mode).

## Menu bar

| Title | Meaning |
|---|---|
| eye 2:14 | awake, 2 h 14 min left |
| eye 2:14 laptop | awake, also with the lid closed |
| eye sparkles | awake while agents run |
| eye hourglass | awake while a process runs |
| struck-through eye | not keeping awake |
| struck-through eye · laptop | lid mode ticked; applies to the next session |

## Features

- **While agents run**: awake while any [agent-deck](https://github.com/asheshgoplani/agent-deck)
  session is `running`; stops 10 min after the last one finishes. An unreadable agent-deck counts as
  busy. Shown only when `agent-deck` and `jq` are in `~/.local/bin`, `/opt/homebrew/bin` or
  `/usr/local/bin`.
- **While a process runs**: pick one of your five busiest processes, or any by name or PID; Wakey
  stops when it exits (`caffeinate -w`). Good for long builds, downloads and renders.
- **Timed**: 1h / 3h / 8h, Until ▸ any hour or Custom HH:MM, Indefinitely. A notification 5 minutes
  before a timed session ends offers +1h.
- **Terminal runs**: lists `caffeinate` runs you started elsewhere, with time left and a stop item.
  Runs started by Claude Code (which holds `caffeinate -i -t 300` while it works) are not listed.
- **Battery cutoff**: stops on battery power below Off / 10 / 20 / 30 / 50% (default 20%). Enforced by
  a helper beside each session, so it holds even if Wakey.app is not running.
- **Sleep displays now** (`pmset displaysleepnow`); the Mac stays awake.
- **Quit Wakey** ends the session too; hold Option for "Quit Wakey, keep awake".

Wakey makes no network calls except when you choose Check for updates….

## Closed lid

caffeinate cannot keep a Mac awake with the lid closed; `pmset disablesleep` can, and it needs root.
Menu → "Also with lid closed: set up…" installs `/etc/sudoers.d/wakey` after an admin prompt,
allowing exactly `pmset -a disablesleep 1` and `0` without a password.

A Mac kept awake in a closed bag can get hot: prefer a timed or process session to Indefinitely, and
keep the battery cutoff on.

Wakey sets `disablesleep 0` when the session ends (the session's helper, plus a check on every
refresh). If it is ever left on, the Mac will not sleep with the lid closed: check with
`pmset -g | grep SleepDisabled`, clear with `sudo pmset -a disablesleep 0`.
Remove the rule: `sudo rm /etc/sudoers.d/wakey`.

## How it works

`wakey.sh` holds all logic and state (`~/.local/state/wakey`) and prints its menu in the
SwiftBar/xbar text format, so it also runs as a SwiftBar plugin. `Wakey.app` renders that output
natively: it runs the engine as the menu opens, after each action, on wake, and every minute for the
title.

Tests: `tests/engine-test.sh` runs the engine against fake `pmset`, `sudo`, `agent-deck` and
`osascript`; CI runs it with the build on every push.

Releases: `tools/release.sh X.Y.Z` on a clean `main` tags, uploads the source tarball that
`install.sh` and the formula fetch, and pins the formula to it.

## License

MIT, see [LICENSE](LICENSE).
