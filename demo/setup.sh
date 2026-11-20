#!/bin/bash
# Builds a throwaway home folder full of developer junk on a 6 GB RAM disk for the demo recording.
# The scanner counts only bytes a file doesn't share, so the junk is real data, not clones.
# Remove it with: diskutil eject /Volumes/MDCDemo
set -euo pipefail
V=/Volumes/MDCDemo
if [ ! -d "$V" ]; then
  dev=$(hdiutil attach -nomount ram://12582912 | awk '{print $1}')
  diskutil erasevolume APFS MDCDemo "$dev" >/dev/null
fi
H="$V/home"
rm -rf "$H"; mkdir -p "$H"

junk() { # junk <path> <MB>
  mkdir -p "$H/$1"
  dd if=/dev/zero of="$H/$1/blob" bs=1m count="$2" 2>/dev/null
}

junk "Library/Developer/Xcode/DerivedData/Pocket-bxqzkfjdtrewcm" 820
junk "Library/Developer/Xcode/DerivedData/Weather-ahgtrplomqzwse" 410
junk "Library/Developer/Xcode/DerivedData/Notes-cvbnmlkjhgfdsa" 140
junk "Library/Developer/Xcode/iOS DeviceSupport/iPhone16,2 18.1 (22B83)" 610
junk "Library/Developer/Xcode/UserData/Previews" 115
junk "Library/Developer/Xcode/Archives/2026-10-02/Pocket 2.4.xcarchive" 200
junk "Library/Developer/CoreSimulator/Caches" 160
junk ".npm/_cacache" 270
junk "Library/pnpm/store" 190
junk "Library/Caches/pip" 75
junk ".cargo/registry/cache" 180
junk ".gradle/caches" 290
junk "Library/Caches/Homebrew" 115
junk "Library/Caches/ms-playwright" 140
junk ".ollama/models" 300
junk ".claude/projects/-Users-me-Code-web-app" 35

junk "Code/web-app/node_modules" 160; echo '{}' > "$H/Code/web-app/package.json"
junk "Code/web-app/.next" 55
junk "Code/landing/node_modules" 100; echo '{}' > "$H/Code/landing/package.json"
junk "Code/api/target" 430; touch "$H/Code/api/Cargo.toml"
junk "Code/ml/.venv" 90; touch "$H/Code/ml/.venv/pyvenv.cfg"

# Junk is old junk: anything touched in the last 3 hours is skipped.
find "$H" -exec touch -h -t 202609011200 {} +
