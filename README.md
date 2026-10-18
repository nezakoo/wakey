# Wakey

macOS menu-bar app that keeps the Mac awake (`caffeinate -dis`): for 1h / 3h / 8h, until any clock
time, indefinitely, or while agent-deck agents are running. Optional closed-lid mode.

## Install

Needs macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`). Wakey is built from
source on your Mac, so there is no unsigned download for Gatekeeper to block.

    curl -fsSL https://raw.githubusercontent.com/nezakoo/wakey/main/install.sh | bash

Or from a clone: `./build.sh && cp -R build/Wakey.app /Applications/ && open /Applications/Wakey.app`.

Then Wakey menu → Open at login. Run the same command again to update.

Uninstall: Quit Wakey, then `rm -rf /Applications/Wakey.app ~/.local/state/wakey`
(and `sudo rm /etc/sudoers.d/wakey` if you set up closed-lid mode).

## Menu bar

| Title | Meaning |
|---|---|
| eye 2:14 | awake, 2 h 14 min left |
| eye 2:14 laptop | awake, also with the lid closed |
| eye sparkles | awake while agents run |
| struck-through eye | not keeping awake |
| struck-through eye · laptop | lid mode ticked; applies to the next session |

## Features

- Presets, Until ▸ any hour or Custom HH:MM, Indefinitely, +1h on a timed session.
- While agents run: awake while any [agent-deck](https://github.com/asheshgoplani/agent-deck) session
  is `running`; stops 10 min after the last one finishes. An unreadable agent-deck counts as busy.
  Shown only when `agent-deck` and `jq` are in `~/.local/bin`, `/opt/homebrew/bin` or `/usr/local/bin`.
- Lists caffeinate runs started from a terminal, with time left and a stop item.
- Battery cutoff: stops on battery power below Off / 10 / 20 / 30 / 50% (default 20%).
- Sleep displays now (`pmset displaysleepnow`); the Mac stays awake.

## Closed lid

caffeinate cannot keep a Mac awake with the lid closed; `pmset disablesleep` can, and it needs root.
Menu → "Also with lid closed: set up…" installs `/etc/sudoers.d/wakey` after an admin prompt,
allowing exactly `pmset -a disablesleep 1` and `0` without a password.

A Mac kept awake in a closed bag can get hot and drain its battery: use a timed session, keep the
battery cutoff on, and keep Wakey running (the cutoff is checked by the app, not by the session).

Wakey sets `disablesleep 0` when the session ends (watcher process, plus a check on every refresh).
If it is ever left on, the Mac will not sleep with the lid closed: check with
`pmset -g | grep SleepDisabled`, clear with `sudo pmset -a disablesleep 0`.
Remove the rule: `sudo rm /etc/sudoers.d/wakey`.

## How it works

`wakey.sh` holds all logic and state (`~/.local/state/wakey`) and prints its menu in the
SwiftBar/xbar text format, so it also runs as a SwiftBar plugin. `Wakey.app` runs it every 10 s
and renders that output natively.

Tests: `tests/engine-test.sh` runs the engine against fake `pmset`, `sudo` and `agent-deck`.
