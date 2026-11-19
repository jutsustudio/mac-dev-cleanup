# Public stats: how much disk space developer junk takes on macOS

Compiled 2026-11-19 from public sources.

**Legend.** `M` = measured and reported by a real user, `E` = typical-range estimate from a blog or cleaner-vendor page (method not stated), `D` = official docs.
Dates are the page's own; "yr n/s" = year not shown on the page. Vendor "typical size" tables (ClearDisk, nixeton/dev.to, MacPaw) are `E` and mostly come from cleaner-tool marketing: quote them as "typically", never as measurements.
Safe = regenerable without loss of work. Cost = what you pay after deleting.

## 1. Headline numbers (the ones worth quoting)

| Claim | Number | Type | Source (date) |
|---|---|---|---|
| Cursor `globalStorage/state.vscdb` single file | 188.3 GB (231.3 GB for the whole Cursor dir) | M | [Cursor forum](https://forum.cursor.com/t/cursor-is-using-231-gb-on-my-mac-i-guess-ive-been-building-an-operating-system-without-knowing-it/165602) (Jul 13 2026) |
| Codex `~/.codex/sessions`, subagent fan-out | ~755 GiB (731.5 GiB from one parent thread) on macOS | M | [openai/codex#34061](https://github.com/openai/codex/issues/34061) (Jul 18 2026; a later comment says ~890 GiB, Aug 27 2026) |
| node_modules across one `~/dev` | 128 folders, 58.68 GB | M | [Flavio Copes](https://flaviocopes.com/npkill/) (Oct 2026) |
| Xcode `~/Library/Developer` | "almost 90 GB" | M | [Apple forums 812408](https://developer.apple.com/forums/thread/812408) (Jan 2026) |
| Xcode 16.3 DerivedData | 20.65 -> 47.66 GB after upgrade; `CompilationCache.noindex` = 27 of 31 GB | M | [Apple forums 779612](https://developer.apple.com/forums/thread/779612) (Apr-Jun 2025) |
| Previews cache | 165 GB reported; "saved over 60 gigs" | M | [Apple forums 682439](https://developer.apple.com/forums/thread/682439) and [search summary of Stack Overflow/CodeCrew threads](https://codecrew.codewithchris.com/t/xcode-storage-space-management/16158) (dates n/s) |
| "How I saved 100 GB": freed Docker.raw 64 GB, AVDs 35 GB (of ~66 GB), Android images ~20 GB (of ~40 GB), node_modules ~10 GB | ~129 GB freed | M | [thoughtbot](https://thoughtbot.com/blog/how-i-saved-100-gb-of-disk-space-on-my-mac) (May 30 2024) |
| Mole's own demo | "95 GB of macOS junk" in one run | M | [recca0120 write-up](https://recca0120.github.io/en/2026/03/09/mole-macos-cleaner/) (Mar 9 2026) |

## 2. Per-category table

### 2.1 Xcode and Apple toolchain

| Category | Path | Reported size (GB) | Source, date | Safe? | Cost of deleting |
|---|---|---|---|---|---|
| DerivedData | `~/Library/Developer/Xcode/DerivedData` | 20.65-47.66 (one project set, Xcode 16.3) M; 10-80 E | [Apple 779612](https://developer.apple.com/forums/thread/779612) Apr 2025; [ClearDisk](https://bysiber.github.io/cleardisk/blog/free-disk-space-mac-developer) Mar 2025 | Yes. accepted forum answer: "safe to delete at any time" ([Apple 812408](https://developer.apple.com/forums/thread/812408), Jan 2026) | Full rebuild and re-index per project; one guide says 1-5 min ([cacheclear](https://cacheclear-site.pages.dev/blog/xcode-deriveddata-clear/)). Quit Xcode first |
| Xcode Archives | `~/Library/Developer/Xcode/Archives` | 2-30 E (sources conflict: 1-10, 2-30, 5-30) | [ClearDisk](https://bysiber.github.io/cleardisk/blog/free-disk-space-mac-developer) Mar 2025; [nixeton](https://dev.to/nixeton/your-dev-tools-are-why-your-mac-is-full-heres-how-to-reclaim-50-100gb-3n8b) | Only if never shipped. Apple advice (per Mole): keep the archive + dSYM of every distributed build | Cannot re-symbolicate crash reports for shipped builds; cannot re-export. [Mole Xcode post](https://mole.fit/blog/how-to-clean-up-xcode-mac.md) (Jul 12 2026) |
| iOS / watchOS DeviceSupport | `~/Library/Developer/Xcode/iOS DeviceSupport`, `watchOS DeviceSupport` | 2-5 per OS version, 5-20 total E; 121 GB on a 256 GB Mac M (poster) | [ClearDisk](https://bysiber.github.io/cleardisk/blog/xcode-simulators-device-support-cleanup-mac.html) Jul 2025; [DevCleaner README](https://github.com/vashpan/xcode-dev-cleaner) (2-5 GB per OS); 121 GB figure via [search summary](https://diskport-website.pages.dev/blog/xcode-ios-devicesupport-safe-delete.html) | Yes for OS versions you no longer debug on (Apple answer in [812408](https://developer.apple.com/forums/thread/812408)) | Re-copies device symbols next time that device is connected: "30 s to a few minutes" (guide estimate) |
| CoreSimulator devices | `~/Library/Developer/CoreSimulator/Devices` | 10-40 E (2-15 in another guide) | [ClearDisk](https://bysiber.github.io/cleardisk/blog/xcode-simulators-device-support-cleanup-mac.html) | Via `simctl`/Xcode only. Apple DTS: do not manage by hand ([812408](https://developer.apple.com/forums/thread/812408)) | Loses app data and simulator state; `xcrun simctl delete unavailable` skips Trash. One dev: +20 GB freed, another 50+ GB incl. runtimes ([summary](https://developer.apple.com/forums/thread/773153)) |
| Simulator runtimes | `/Library/Developer/CoreSimulator/Volumes` (and Xcode Settings > Platforms) | ~8 per iOS 26.2 runtime M; 7.9 GB iOS 26.5 + 3.0 GB dyld cache M | [Apple 812792](https://developer.apple.com/forums/thread/812792) (iOS 26.2); [claude-code issue 88234](https://claudeissues.com/issue/88234-claude-desktop-local-agent-silently-downloads-an-8-5-gb-ios-simulator-runtime-an) (single report). Xcode 26 beta5 shrank tvOS runtime 4.83 -> 3.62 GB ([Bitrise](https://bitrise.io/blog/post/xcode-app-size-reduction-in-26-0-beta-5)) | Yes, except the runtime you need | Re-download 5-8 GB (Apple forums show downloads stalling at "Preparing..." on Xcode 26.6: [thread 843992](https://developer.apple.com/forums/thread/843992)) |
| Xcode Previews | `~/Library/Developer/Xcode/UserData/Previews` | 20+ , 80, 165 M | [Apple 682439](https://developer.apple.com/forums/thread/682439); [CodeCrew](https://codecrew.codewithchris.com/t/xcode-storage-space-management/16158) | Yes: `xcrun simctl --set previews delete all` | Previews rebuild their simulator on next use |
| SwiftPM cache | `~/Library/Caches/org.swift.swiftpm`, `~/Library/org.swift.swiftpm` | 1-5 E; 3-8 per reader comment | [ClearDisk](https://bysiber.github.io/cleardisk/blog/free-disk-space-mac-developer); [nixeton](https://dev.to/nixeton/your-dev-tools-are-why-your-mac-is-full-heres-how-to-reclaim-50-100gb-3n8b) | Yes | Re-resolve and re-download packages |
| CocoaPods cache | `~/Library/Caches/CocoaPods`, `~/.cocoapods/repos` | 1-10 E; repos/trunk 1.2 GB in one example | [ClearDisk](https://bysiber.github.io/cleardisk/blog/cocoapods-cache-cleanup-mac.html) | Yes | Re-download pods on next `pod install` |
| Xcode docs cache | `~/Library/Developer/Xcode/DocumentationCache` | no figure | [Apple 812408](https://developer.apple.com/forums/thread/812408) | Yes (delete `DocumentationIndex` too) | Rebuilt, "likely smaller" |

### 2.2 JavaScript

| Category | Path | Reported size (GB) | Source, date | Safe? | Cost |
|---|---|---|---|---|---|
| node_modules, per project | project dirs | 0.2-0.5 each (vendor-neutral claim) | [Mole dev-caches post](https://mole.tw93.fun/blog/how-to-clear-dev-caches-mac) (Jun 3 2026) | Yes (lockfile restores) | `npm/pnpm install`: network + minutes |
| node_modules, total | whole dev dir | 58.68 (128 dirs, ~0.46 avg, computed) M; ~10 M; 7 M; 95.53 (comment) M | [Copes](https://flaviocopes.com/npkill/) Oct 2026; [thoughtbot](https://thoughtbot.com/blog/how-i-saved-100-gb-of-disk-space-on-my-mac) May 2024; [dev.to/joelvarty](https://dev.to/joelvarty/i-just-used-npkill-to-clean-up-7-gb-of-disk-space-4o5g) (date n/s); [Hashnode comment](https://hashnode.com/posts/delete-unused-nodemodules-from-your-computer-like-a-pro-with-npkill/602e148819bec71cf119ae7d) | Yes, except projects you are working on | Same; npkill uses `rm -rf`, no Trash ([Copes](https://flaviocopes.com/npkill/)) |
| npm cache | `~/.npm/_cacache` | 1-10 E | [ClearDisk](https://bysiber.github.io/cleardisk/blog/npm-yarn-pnpm-cache-cleanup-mac.html) Jul 2025 | Yes | Re-fetch packages |
| yarn cache | `~/Library/Caches/Yarn`, `~/.yarn/berry/cache` | 1-10 / 0.5-5 E | same | Yes | Re-fetch |
| pnpm store | `~/Library/pnpm/store` (`pnpm store path`) | 2-15 E | same | `pnpm store prune` is safe; manual delete breaks hardlinked/reflinked node_modules | `du` over-reports APFS reflinks ([summary](https://flaviocopes.com/managing-node-modules-efficiently/)) |
| bun cache | `~/.bun/install/cache` | no sourced figure | n/a | Yes | Re-fetch |
| Playwright / Puppeteer browsers | `~/Library/Caches/ms-playwright`, `~/.cache/puppeteer` | 1.0-1.6 all three engines (E); older docs 281/187/180 MB per engine | [qaskills 2026](https://qaskills.sh/blog/playwright-vs-puppeteer-bundle-size-2026) | Yes (`playwright uninstall --all`) | `npx playwright install` re-download ~1 GB |
| nvm / fnm Node versions | `~/.nvm`, `~/.fnm` | nvm 2-10, fnm 1-5 E; ~70-100 MB per Node version | [ClearDisk](https://bysiber.github.io/cleardisk/blog/version-manager-cache-cleanup-mac.html) Mar 2025 | Old versions yes | `nvm install` re-download; global npm packages are per version and lost |

### 2.3 Python

| Category | Path | Reported size (GB) | Source, date | Safe? | Cost |
|---|---|---|---|---|---|
| pip cache | `~/Library/Caches/pip` | 1-3 / 1-5 E | [nixeton](https://dev.to/nixeton/your-dev-tools-are-why-your-mac-is-full-heres-how-to-reclaim-50-100gb-3n8b); [ClearDisk](https://bysiber.github.io/cleardisk/blog/free-disk-space-mac-developer) | Yes (`pip cache purge`) | Re-download wheels |
| uv cache | `~/.cache/uv` | no typical figure found; docs: torch/scipy "multiple GB" | [uv docs](https://docs.astral.sh/uv/concepts/cache) | `uv cache prune` safe; do not `rm -rf` (corruption warning in one guide, [pydevtools](https://pydevtools.com/handbook/how-to/how-to-manage-uv-cache-size/)) | Re-download |
| poetry cache | `~/Library/Caches/pypoetry` | no sourced figure | n/a | Yes | Re-download |
| conda envs / pkgs | `~/miniconda3/envs`, `~/miniconda3/pkgs` | envs 2-30 E; pkgs 10-500 MB or 2-10 GB (sources disagree) | [nixeton conda](https://dev.to/nixeton/dont-let-conda-eat-your-hard-drive-python-environment-cleanup-for-mac-1oi8) | `conda clean --all` safe; deleting an env loses it | Recreate env (minutes, GBs) |
| venvs | `.venv` in projects | plain 12-50 MB; with torch ~5-7 GB each (5 copies x 3.5 GB = 21 GB) | [PyTorch forum](https://discuss.pytorch.org/t/pytorch-install-is-that-large-5-gbs/213629); [guide](https://dev.to/nixeton/dont-let-conda-eat-your-hard-drive-python-environment-cleanup-for-mac-1oi8) | Yes if `requirements`/lock exists | Reinstall; torch needs a multi-GB download |

### 2.4 Rust and Go

| Category | Path | Reported size (GB) | Source, date | Safe? | Cost |
|---|---|---|---|---|---|
| target/, per project | `<proj>/target` | 5-15 E (debug 2-10, release 1-5); counter-example: 4 small projects = 1.07 GB total M | [nixeton](https://dev.to/nixeton/cargo-target-directories-why-rust-projects-eat-10gb-each-26kd) (Apr 29, yr n/s); [thisdavej](https://thisdavej.com/freeing-up-gigabytes-reclaiming-disk-space-from-rust-cargo-builds/) (Apr 22 2025) | Yes | Full recompile (minutes to tens of minutes); `cargo-sweep` keeps recent artifacts |
| target/ extremes | same | "75 GB" Reddit thread (claim, source behind login); "hundreds of GB" | [BestHub](https://www.besthub.dev/articles/why-a-rust-project-can-swallow-75-gb-of-disk-space-and-how-to-tame-cache-bloat-in-rust-and-go-0b7c8efc837e) (Jun 30 2026) | Yes | Same |
| target/ per git worktree | one target per worktree | no sourced figure. Inference: N worktrees = N x per-project size unless `CARGO_TARGET_DIR` is shared | [cargo-sweep note](https://users.rust-lang.org/t/cleaning-target-folders-with-cargo-sweep/84229) on shared dirs | Yes | Same |
| cargo registry/git | `~/.cargo/registry`, `~/.cargo/git` | 1-5 E (cache 0.5-2, src 0.5-3) | [nixeton](https://dev.to/nixeton/cargo-target-directories-why-rust-projects-eat-10gb-each-26kd) | Yes (Mole says leave to cargo's own GC) | Re-download crates |
| rustup toolchains | `~/.rustup/toolchains` | 0.5-1 per toolchain E; ~3 total with 3 toolchains M; 36 with many nightlies M | [ClearDisk](https://bysiber.github.io/cleardisk/blog/version-manager-cache-cleanup-mac.html); [rust forum/SO summary](https://users.rust-lang.org/t/manual-global-installation/33528) | Unused nightlies yes (`rustup toolchain uninstall`) | Re-download 0.5-1 GB each |
| Go module / build cache | `~/go/pkg/mod`, `~/Library/Caches/go-build` | 1-3 / 0.5-2 E (ClearDisk: 1-10) | [nixeton](https://dev.to/nixeton/homebrew-gradle-and-the-hidden-caches-eating-your-macs-storage-3f9e); [ClearDisk](https://bysiber.github.io/cleardisk/blog/free-disk-space-mac-developer) | Yes (`go clean -modcache -cache`) | Re-download and recompile |

### 2.5 JVM and Android

| Category | Path | Reported size (GB) | Source, date | Safe? | Cost |
|---|---|---|---|---|---|
| Gradle caches | `~/.gradle/caches` (+ `wrapper/dists` 0.5-2) | 5-15 E; 2-20 E | [nixeton](https://dev.to/nixeton/homebrew-gradle-and-the-hidden-caches-eating-your-macs-storage-3f9e); [ClearDisk](https://bysiber.github.io/cleardisk/blog/free-disk-space-mac-developer) | Yes | Re-download dependencies; slow first build |
| Maven | `~/.m2/repository` | 2-10 E | [nixeton](https://dev.to/nixeton/homebrew-gradle-and-the-hidden-caches-eating-your-macs-storage-3f9e) | Mostly. Mole warns it can hold non-downloadable artifacts | Re-download |
| Android system images | `~/Library/Android/sdk/system-images` | ~40 total M; 5-10 each | [thoughtbot](https://thoughtbot.com/blog/how-i-saved-100-gb-of-disk-space-on-my-mac) May 2024; [dissectmac](https://dissectmac-com.pages.dev/blog/android-emulator-cleanup) | Yes via SDK Manager | Re-download 5-10 GB each |
| AVDs | `~/.android/avd` | ~66 total, one Pixel AVD 45 -> 10 GB after wipe M | [thoughtbot](https://thoughtbot.com/blog/how-i-saved-100-gb-of-disk-space-on-my-mac) | Wipe or delete in Device Manager | Lose emulator state and installed apps |

### 2.6 Containers

| Category | Path | Reported size (GB) | Source, date | Safe? | Cost |
|---|---|---|---|---|---|
| Docker Desktop disk image | `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` | 64 M (thoughtbot); 40 file / 67 total M; docs example: 64 GB max, ~2.2 GB actually allocated | [thoughtbot](https://thoughtbot.com/blog/how-i-saved-100-gb-of-disk-space-on-my-mac) May 2024; [nixeton Docker](https://dev.to/nixeton/docker-ate-your-disk-reclaiming-20-50gb-on-macos-4k86) (Apr 29, yr n/s); [Docker docs](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/) | Images/cache yes; volumes hold data | `docker system prune` does not always shrink the host file; docs say lowering max size deletes ALL images and containers |
| `docker system df` reclaimable | inside VM | sample output: images 18.72 (16.48 reclaimable), volumes 8.31 (7.89), build cache 14.2 (14.2); author says prune typically frees 15-30 | [nixeton Docker](https://dev.to/nixeton/docker-ate-your-disk-reclaiming-20-50gb-on-macos-4k86) (sample, not stated as measured); format per [Docker CLI docs](https://docs.docker.com/reference/cli/docker/system/df/) | Yes for unused images/build cache | Re-pull and rebuild. Note `df` does not report the host file size, which is often larger |
| OrbStack | `~/.orbstack/data/data.img` | shows 8 TB apparent (sparse); real use via `du -h` | [OrbStack FAQ](https://docs.orbstack.dev/faq) | Same as Docker | `ls -l` / backup tools mislead; use `du` |
| Homebrew | `~/Library/Caches/Homebrew`, old kegs | cache 2-5, old kegs 0.5-3, logs 0.1-0.5 E | [nixeton](https://dev.to/nixeton/homebrew-gradle-and-the-hidden-caches-eating-your-macs-storage-3f9e) | Yes (`brew cleanup --prune=all`) | Re-download bottles |

### 2.7 Local AI models

| Category | Path | Reported size (GB) | Source, date | Safe? | Cost |
|---|---|---|---|---|---|
| Ollama | `~/.ollama/models` | per model 4.1-4.7 (7-8B), ~26 (Mixtral 8x7B), ~40 (70B Q4); 5-6 models easily 50-100 | [insiderllm](https://insiderllm.com/guides/managing-multiple-models-ollama/) / [Ollama list docs](https://mintlify.com/ollama/ollama/cli/list) (dates n/s) | Use `ollama rm`, never delete blobs by hand | Re-pull 4-40 GB per model |
| LM Studio | `~/.lmstudio/models` | official example: 47 models = 160.78 GB | [LM Studio docs `lms ls`](https://lmstudio.ai/docs/cli/local-models/ls) | Remove via app/`lms` | Re-download |
| Hugging Face | `~/.cache/huggingface/hub` | no typical figure; docs sample "Saved 8.6G" | [HF docs](https://huggingface.co/docs/huggingface_hub/how-to-cache) | Yes (`huggingface-cli delete-cache`) | Re-download weights |

### 2.8 AI coding agents and editors

| Category | Path | Reported size | Source, date | Safe? | Cost |
|---|---|---|---|---|---|
| Claude Code transcripts | `~/.claude/projects/<project>/*.jsonl` | 565 MB after 3 weeks (732 MB total ~/.claude) M; 2.7 GB / 2,362 files M; 2,707 MB (+ debug 734 MB, file-history 188 MB) M; 3.2 GB macOS after ~2 months M; 7.9 GB / 71 sessions M (snippet) | [bestagent](https://bestagent.dev/claude-code-disk-usage-cleanup) Jun 11 2026; [Mole AI post](https://mole.fit/blog/how-to-clean-up-ai-coding-tools-mac) Aug 21 2026 (upd Nov 2); [anthropics/claude-code#24207](https://github.com/anthropics/claude-code/issues/24207) Feb 8 2026 | Old sessions yes. Never touch `settings.json`, `~/.claude.json`, credentials, `memory/` | `--resume`/`--continue` lose those sessions; `/rewind` loses `file-history`. `cleanupPeriodDays` default 30, covers sessions only, not `debug/` or `file-history/` ([bestagent](https://bestagent.dev/claude-code-disk-usage-cleanup)) |
| Claude `file-history` extreme | `~/.claude/file-history` | 300 GB (one user, issue #10107) | [#24207](https://github.com/anthropics/claude-code/issues/24207) | Yes | `/rewind` lost |
| Claude Code binaries | `~/.local/share/claude/versions/*` | 5 versions x 293-306 MB | [Mole AI post](https://mole.fit/blog/how-to-clean-up-ai-coding-tools-mac) | Superseded versions yes | Re-download |
| Codex sessions | `~/.codex/sessions`, `archived_sessions` | 9.8 GB (Mole author) M; 25.45 GB / 608 sessions, largest 6.7 GB (in-app warning) M; ~755-890 GiB runaway subagent case M | [Mole AI post](https://mole.fit/blog/how-to-clean-up-ai-coding-tools-mac); [codex#34061](https://github.com/openai/codex/issues/34061); [community post via search](https://community.openai.com/t/must-be-improved-sections-and-features/1389757) | Old sessions yes; archiving only moves files, frees nothing | `codex resume` loses history; no official cleanup workflow ([codex#20230](https://github.com/openai/codex/issues/20230)) |
| Codex releases | `~/.codex/packages/standalone/releases` | 5 x 262-310 MB | [Mole AI post](https://mole.fit/blog/how-to-clean-up-ai-coding-tools-mac) | Superseded yes | Re-download |
| Cursor global DB | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` (+ `.backup`) | 12.4 + 12.2 (Jun 2026); 61.1 (Sep 2026); 125 (Sep 2026); 188.3 / 231.3 (Jul 2026); 3.1 -> 97 over 2 months, 49.8 + 50.5 (titles) M | [Cursor forum 172127](https://forum.cursor.com/t/cursor-storage-has-grown-to-125gb-on-my-mac-how-can-i-safely-reduce-it-without-losing-history-context/172127), [165602](https://forum.cursor.com/t/cursor-is-using-231-gb-on-my-mac-i-guess-ive-been-building-an-operating-system-without-knowing-it/165602), [162623](https://forum.cursor.com/t/macos-state-vscdb-grew-to-12-4-gb-and-state-vscdb-backup-grew-to-12-2-gb-on-a-256-gb-macbook-air-seeking-safe-remediation-guidance/162623), [166013](https://forum.cursor.com/t/state-vscdb-grew-from-3-1-gb-97-gb-macos/166013), [147615](https://forum.cursor.com/t/surely-its-a-bug-that-it-49-8gb-for-state-vscdb-backup-and-50-54gb-for-state-vscdb/147615) | `.backup` yes (Cursor staff). Do not delete `state.vscdb` itself: chats stick on "Loading Chat..." | Staff route: `GC Agent KV Blobs` (lossless, needs free space ~ file size) then `Delete Old Chats...` (permanent) |
| Cursor workspaceStorage | `.../Cursor/User/workspaceStorage` | 63 MB in one case; no large figure found | [Cursor forum 162623](https://forum.cursor.com/t/macos-state-vscdb-grew-to-12-4-gb-and-state-vscdb-backup-grew-to-12-2-gb-on-a-256-gb-macbook-air-seeking-safe-remediation-guidance/162623) | Per-project chats live here | Lose that project's chats |
| Cursor agent copies | `.../globalStorage/anysphere.cursor-agent-worker/.../versions` | 7 releases = 4.1 GB | [Mole AI post](https://mole.fit/blog/how-to-clean-up-ai-coding-tools-mac) | Old releases yes | Re-download |
| VS Code | `~/Library/Application Support/Code/{CachedData,CachedExtensionVSIXs,User/workspaceStorage}` | 2-5 E (whole dir); CachedExtensionVSIXs ~0.5 (Windows anecdote); no workspaceStorage figure | [nixeton](https://dev.to/nixeton/homebrew-gradle-and-the-hidden-caches-eating-your-macs-storage-3f9e) | Caches yes | Re-index on next open |
| JetBrains | `~/Library/Caches/JetBrains/<product><ver>` | 2-10 E; 2.5-2.9 per old IDE version M; outliers 100+ and 237 GB | [nixeton](https://dev.to/nixeton/homebrew-gradle-and-the-hidden-caches-eating-your-macs-storage-3f9e); [ashishb](https://ashishb.net/programming/intellij-wasting-disk-space/); [JetBrains support](https://intellij-support.jetbrains.com/hc/en-us/community/posts/207046705-100-GB-cache), [237 GB](https://intellij-support.jetbrains.com/hc/en-us/community/posts/9266483399954/comments/9266736117778) (old threads) | Yes; old-version dirs are the usual culprit | Full re-index; local history kept unless opted in |

## 3. Tool coverage matrix

Y = documented as cleaned, R = review-only or opt-in, - = not documented as covered, ? = could not verify.
Sources: [Mole README](https://github.com/tw93/Mole) (75.6k stars, GPL-3.0) + [Mole docs](https://mole.tw93.fun/docs) + [Mole Xcode](https://mole.fit/blog/how-to-clean-up-xcode-mac.md) / [simulator](https://mole.fit/blog/how-to-clean-up-ios-simulator-mac.md) / [AI](https://mole.fit/blog/how-to-clean-up-ai-coding-tools-mac) posts; [mac-cleaner-cli (guhcostan)](https://github.com/guhcostan/mac-cleaner-cli) (~2k stars, MIT); [DevCleaner for Xcode](https://github.com/vashpan/xcode-dev-cleaner) (1.6k, GPL-3.0); [npkill](https://github.com/voidcosmos/npkill) (9.6k, MIT); [kondo](https://github.com/tbillington/kondo) (2.6k).
"devcleaner.app" (multi-ecosystem menu bar app, "22 ecosystems") is described only on [Product Hunt](https://www.producthunt.com/p/devcleaner-reclaim-gbs-from-dev-tools/devcleaner-1-6-2-hibernate-docker-compose-projects-volumes-images-and-one-click-polyglot-restore); its own site was not reachable in search, so its column is vendor-claim only.

| Category | Mole | mac-cleaner-cli | DevCleaner (Xcode) | npkill | kondo | devcleaner.app (claim) |
|---|---|---|---|---|---|---|
| DerivedData | R (Mac app list) | Y (`dev-cache`) | Y | - | - | Y |
| Xcode Archives | - (deliberately) | - | Y | - | - | ? |
| iOS/watchOS DeviceSupport | Y (list) | - | Y | - | - | ? |
| CoreSimulator devices | - | - | - (README lists only logs) | - | - | Y (simulators) |
| Simulator runtimes | Y (unused 60 d, via `simctl`) | - | - | - | - | ? |
| Xcode Previews | - | - | - | - | - | ? |
| SwiftPM cache | - | - | - | - | R (`.build` project dirs) | ? |
| CocoaPods cache | R (Mac app) | Y | - | - | - | ? |
| node_modules | Y (`mo purge`) | Y | - | Y | Y | Y |
| npm / yarn / pnpm / bun caches | Y (npm, pnpm named in CLI); R (all four in app) | Y (npm, yarn) | - | - | - | Y |
| Playwright / Puppeteer browsers | - | - | - | - | - | ? |
| nvm / fnm Node versions | - | - | - | - | - | ? |
| pip / uv / poetry / conda caches | ? (pip hinted) | Y (pip) | - | - | - | ? |
| venvs, `__pycache__` | Y (`venv` in purge) | - | - | Y (profile) | Y (Python, Pixi) | ? |
| Rust `target/` | Y | Y | - | Y (profile) | Y | ? |
| cargo registry, rustup toolchains | ? (custom Rust dirs mentioned in release notes) | - | - | - | - | ? |
| Go module/build cache | ? (Go in earlier README) | Y (opt-in artifacts only) | - | - | - | ? |
| Gradle / Maven caches | R (Gradle) | - | - | - | Y (project `build`/`target` only) | Y (Gradle) |
| Android SDK images / AVDs | - | - | - | - | - | ? |
| Homebrew cache | ? | Y | - | - | - | Y |
| Docker / OrbStack | ? | Y (images, build cache; never volumes) | - | - | - | Y (Docker, OrbStack, Colima) |
| Ollama / LM Studio / HF models | R (Ollama unused 1 mo, Mac app) | - | - | - | - | Y (Ollama) |
| Claude Code transcripts | R (Mac app, by retention); CLI protects them | - | - | - | - | ? |
| Codex sessions | R (Mac app); CLI protects them | - | - | - | - | ? |
| Cursor state.vscdb | - | - | - | - | - | ? |
| AI agent binaries (old versions) | Y (Claude Code, Codex, Cursor Agent) | - | - | - | - | ? |
| VS Code caches | ? | - | - | - | - | ? |
| JetBrains caches | - (uninstall only) | - | - | - | - | ? |
| git worktrees | - | R (`--risky`) | - | - | - | ? |

Other cleaners seen in search but not verified: [ClearDisk](https://github.com/bysiber/cleardisk), [cargo-clean-all](https://github.com/dnlmlr/cargo-clean-all), [cargo-sweep](https://users.rust-lang.org/t/cleaning-target-folders-with-cargo-sweep/84229), MacPaw CleanMyMac CLI ([AlternativeTo, Jul 2026](https://alternativeto.net/news/2026/7/macpaw-launches-cleanmymac-cli-to-clean-developers-caches-leftovers-and-other-junk-files/)).

## 4. Gaps: nobody covers these well

1. **AI agent transcripts** (`~/.claude/projects`, `~/.codex/sessions`): largest outliers in the data (hundreds of GB), and Mole's CLI explicitly protects them. Only Mole's Mac app offers a retention-based review. Neither Anthropic nor OpenAI ships a cleanup command (cleanup limited to `cleanupPeriodDays` for sessions; [codex#20230](https://github.com/openai/codex/issues/20230)).
2. **Cursor `state.vscdb`**: up to 188 GB, no third-party tool; the only fix is Cursor's own command-palette GC.
3. **Xcode Previews and CoreSimulator devices**: up to 165 GB reported, yet absent from the open-source tools above.
4. **Android SDK images and AVDs**: 60-100 GB in thoughtbot's case, covered by none of these tools.
5. **rustup toolchains, cargo-registry, Playwright browsers, nvm versions, uv cache, HF cache, LM Studio**: no coverage found (or only vendor claims).
6. **Docker.raw host shrink**: tools prune inside the VM, but the host file may stay at peak size; Docker's own fix is to lower the limit, which deletes everything.

## 5. Caveats for README use

- Most per-tool GB ranges are vendor `E` estimates. Safe to quote: the `M` rows with a dated link.
- Several nixeton/dev.to pages show "Apr 29" with no year; treat as undated.
- Cursor 97 GB and 49.8 GB figures come from thread titles only (page not fetched); the 188/231/125/61/12.4 GB ones were fetched.
- Claude Code issue #24207 numbers are from a Windows machine; the macOS comment in the same thread says 3.2 GB after ~2 months.
- Mole star counts: 75.6k per README fetch; other pages quote 38k-66.5k at earlier dates.
- Worktree target multiplication is an inference, not a sourced figure.
