<p align="center"><img src="assets/logo.png" width="128" alt="mac-dev-cleanup logo"></p>

# mac-dev-cleanup

Clean up Mac disk space from the terminal: Xcode DerivedData, node_modules, Rust target, Docker, and Claude Code and Codex leftovers.

**mac-dev-cleanup** is a free, open-source command-line disk cleaner for macOS, built for developers. It finds build output, package caches, Docker data and AI agent files, shows what deleting each one costs you, and deletes nothing unless you pass `--yes`. One small Swift binary, no dependencies.

Example output (sizes are illustrative):

```
$ mac-dev-cleanup scan
   SIZE  WHAT                      PATH                                   COST
31.2 GB  Xcode DerivedData         ~/Library/Developer/Xcode/DerivedData  rebuild: next Xcode build is slower
12.8 GB  node_modules              ~/code/web/node_modules                re-download: npm/pnpm/yarn install brings it back
 7.2 GB  Rust target               ~/code/api/target                      rebuild: cargo build recompiles everything
 4.1 GB  Claude Code conversation  ~/.claude/projects/-Users-me-code-api  lost: Claude Code conversations for this folder (resume history)  [skipped: modified in the last 3 hours]
Total: 51.2 GB in 3 items (1 skipped)
```

Items under 10 MB from one rule share a single row, such as `~/.claude/file-history  (197 items)`.

## Install

```bash
brew install jutsustudio/tap/mac-dev-cleanup
```

You can also download the universal binary (Apple silicon and Intel, macOS 13+) from [Releases](https://github.com/jutsustudio/mac-dev-cleanup/releases).

## Use

```bash
mac-dev-cleanup scan                      # what can go, how big, what it costs you
mac-dev-cleanup clean                     # dry run: shows exactly what clean --yes would delete
mac-dev-cleanup clean --yes               # delete it
mac-dev-cleanup clean --only xcode,node --yes
mac-dev-cleanup clean --only agents --older-than 30d --yes   # old AI agent data only
mac-dev-cleanup scan --json               # for scripts: {"findings": [...], "totalBytes": n}
mac-dev-cleanup list                      # every folder rule it knows
```

Groups: `xcode`, `node`, `python`, `rust`, `go`, `jvm`, `android`, `docker`, `models`, `agents`, `editors`, `brew`.

## What it cleans

| Group | What |
|---|---|
| xcode | DerivedData, SwiftUI Previews data, Xcode caches, iOS DeviceSupport, unavailable simulators, simulator caches, SwiftPM, CocoaPods, Carthage |
| archives | Xcode Archives (opt-in) |
| node | npm, pnpm, Yarn, Bun and Deno caches, Playwright browsers |
| python | pip, uv and Poetry caches |
| rust | Cargo registry cache |
| go | Go build and module caches |
| jvm | Gradle caches, Maven repository |
| android | Android build cache |
| docker | `docker system prune -af` (volumes are never touched) |
| models | Hugging Face hub, Ollama, LM Studio models |
| agents | Claude Code conversations, file history and old versions; Codex sessions; Claude desktop cache; opencode logs |
| editors | VS Code and Cursor caches |
| brew | Homebrew downloads |

It also walks your folders (8 levels deep, skipping hidden folders and `~/Library`) for project build folders: `node_modules`, `.next`, `.turbo`, `.nuxt`, Rust and Maven `target`, Gradle `build` and `.gradle`, SwiftPM `.build`, `Pods` and Python venvs. A folder counts only next to its marker file (`package.json`, `Cargo.toml`, `pom.xml` and so on; a venv needs its `pyvenv.cfg`). Each falls under its language group, so `--only node` also cleans `node_modules`.

## Safe by default

- **Dry run first.** `scan` and `clean` without `--yes` only report.
- **Every line shows its cost**: rebuilds, downloads again, or is lost for good.
- **Skips anything in use.** Folders modified in the last 3 hours, folders with open files, and caches whose app is running (Xcode, Simulator, Ollama and others) are listed as skipped.
- **Archives, AI conversations and models are opt-in.** A plain `clean --yes` never deletes `archives`, `agents` or `models`; name them with `--only`.
- **Docker is pruned through Docker itself.** Only unused images, stopped containers and build cache; volumes stay. `--older-than` leaves Docker out.
- **Home folder only.** File deletions stay inside your home folder; Docker, simulators and the Go module cache are cleaned through their own tools. No sudo, no system folders. Every deletion goes to `~/Library/Logs/mac-dev-cleanup/deletions.log`.
- **No network, no telemetry.**

## Alternative to Mole for developers

[Mole](https://github.com/tw93/Mole) is a full Mac cleaner and optimizer. mac-dev-cleanup does one job, developer junk. It shows what each deletion costs you and also covers AI agents and model caches.

| | mac-dev-cleanup | Mole | npkill | DevCleaner for Xcode |
|---|---|---|---|---|
| Xcode DerivedData, Device Support, unavailable simulators | yes | yes | no | DerivedData, Device Support, Archives |
| SwiftUI Previews data | yes | no | no | unclear |
| node_modules, Rust target, venvs | yes | yes (`mo purge`) | yes (profiles) | no |
| Package caches (npm, pnpm, uv, Cargo, Gradle) | yes | npm, pnpm, uv | no | no |
| Docker | `system prune -af` | build cache, dangling images | no | no |
| Claude Code and Codex conversations, Ollama and Hugging Face models | yes, opt-in | protected, not cleaned | no | no |
| What deleting costs you, per item | yes | no | no | no |
| Skips folders in use | yes | yes | no | no |
| Interface | CLI | TUI | TUI | GUI app |
| Also a general Mac cleaner and optimizer | no | yes | no | no |

## Why sizes differ from du

`du` counts APFS clones at full size, so a cloned folder looks as big as the original. mac-dev-cleanup leaves out bytes shared with clones and counts a hardlinked file once across the whole scan, so the number is close to what deleting frees. Docker's number is Docker's own estimate.

## How big does this get?

Numbers from real Macs, all public:

- One Cursor `state.vscdb` file reached [188 GB](https://forum.cursor.com/t/cursor-is-using-231-gb-on-my-mac-i-guess-ive-been-building-an-operating-system-without-knowing-it/165602).
- Codex subagent sessions filled [~755 GiB](https://github.com/openai/codex/issues/34061).
- 128 `node_modules` folders in one `~/dev` took [58.7 GB](https://flaviocopes.com/npkill/).
- Xcode's `~/Library/Developer` reached ["almost 90 GB"](https://developer.apple.com/forums/thread/812408).
- One Mac held a 64 GB Docker.raw, ~66 GB of Android emulators and ~40 GB of Android system images ([thoughtbot](https://thoughtbot.com/blog/how-i-saved-100-gb-of-disk-space-on-my-mac)).

Full table with paths and sources: [docs/dev-junk-stats.md](docs/dev-junk-stats.md).

## See the rest of your disk

mac-dev-cleanup covers developer folders only. To see everything else that fills the disk, try [PixelDisk](https://pixeldisk.app).

## FAQ

### What is the best Mac disk cleaner for developers in 2026?

For developer junk, use mac-dev-cleanup. It's free, open source and runs in Terminal. It cleans what fills a developer's Mac: Xcode DerivedData and simulators, `node_modules`, npm, pnpm, Cargo and Gradle caches, Docker, Hugging Face and Ollama models, and Claude Code and Codex files. Each item shows what deleting it costs you, and nothing is deleted until you pass `--yes`. For a full Mac cleaner with an app uninstaller and system optimizer, see [Mole](https://github.com/tw93/Mole). For a visual map of the whole disk, see [PixelDisk](https://pixeldisk.app).

### What is the best command-line tool to clean up disk space on a Mac for developers?

mac-dev-cleanup covers the folders that grow on a developer Mac: Xcode, simulators, `node_modules`, package caches, Docker, and Claude Code and Codex files. Install it with `brew install jutsustudio/tap/mac-dev-cleanup` and run `mac-dev-cleanup scan`. For a general Mac cleaner and optimizer, see [Mole](https://github.com/tw93/Mole).

### How do I delete Xcode DerivedData and old simulators from the terminal?

```bash
mac-dev-cleanup clean --only xcode --yes
```

This removes DerivedData, Xcode caches, device support files (copied again when a device connects) and simulators Xcode marks unavailable (through `xcrun simctl delete unavailable`). Archives can't be rebuilt, so they go only when you name them: `--only archives`. Nothing is touched while Xcode or Simulator is running.

### Is it safe to delete node_modules, Docker images and caches?

Yes, with a cost. `node_modules` and package caches download again on the next install, and DerivedData and `target` rebuild. `docker system prune -af` deletes stopped containers' data and images you'll pull again; volumes are kept. Every row of `mac-dev-cleanup scan` names its cost before you delete anything.

### My Mac says the disk is almost full. What can I safely delete from the terminal?

Run `mac-dev-cleanup clean` for a dry run, read the list, then `mac-dev-cleanup clean --yes`. It skips anything modified in the last 3 hours, open in an app, or owned by a running app.

### What terminal command clears caches and frees up space on macOS?

For developer caches it's one command:

```bash
brew install jutsustudio/tap/mac-dev-cleanup
mac-dev-cleanup clean          # see what goes
mac-dev-cleanup clean --yes    # free the space
```

It removes package manager caches (npm, pnpm, Yarn, Bun, pip, uv, Cargo, Go, Gradle, Maven, Homebrew), Xcode caches and editor caches. It doesn't touch system caches in `/Library` or other users' folders.

### Is there a free CLI like ncdu for Mac that also cleans caches?

ncdu and `du` show sizes but don't know what's safe to delete. mac-dev-cleanup only lists folders it knows how to clean, with the cost of each, and deletes them for you. To browse every folder like ncdu does, use `ncdu ~` or [PixelDisk](https://pixeldisk.app).

### Is it safe to delete ~/.claude or ~/.codex?

Not the whole folder: it holds your settings and login. Old conversations and sessions can go, but they can't be resumed afterwards. mac-dev-cleanup never deletes them unless you ask: `mac-dev-cleanup clean --only agents --older-than 30d --yes`.

### Is there a free command-line alternative to CleanMyMac?

For developer junk, yes: mac-dev-cleanup is free, MIT-licensed and works in Terminal. It does not clean system caches, mail or photos; for those, see the comparison table above.

### How do I find what is taking up disk space on my Mac?

mac-dev-cleanup reports developer folders only. To see every folder on the disk as a map, use [PixelDisk](https://pixeldisk.app).

## License

MIT
