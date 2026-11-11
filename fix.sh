#!/bin/bash
# Make Frostpunk (Steam, macOS) use OpenAL Soft instead of Apple's OpenAL.
#   bash fix.sh [path/to/Frostpunk.app]          apply (safe to re-run, re-run after every game update)
#   bash fix.sh --undo [path/to/Frostpunk.app]   restore the original binary
# Bash 3.2 compatible (the macOS default).
set -euo pipefail

APPLE_OPENAL=/System/Library/Frameworks/OpenAL.framework/Versions/A/OpenAL
OUR_OPENAL=@executable_path/../Frameworks/libopenal.dylib
LIB_SHA256=3f29b5e4bb5207dfabdcf4ce90902fd1b324445c7ad857fce336fdffa31aa809
HERE="$(cd "$(dirname "$0")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }

undo=0
if [ "${1:-}" = "--undo" ]; then undo=1; shift; fi
APP="${1:-$HOME/Library/Application Support/Steam/steamapps/common/Frostpunk/Frostpunk.app}"
C="$APP/Contents"
BIN="$C/MacOS/Frostpunk"
BAK="$BIN.apple-openal.bak"
DEST="$C/Frameworks/libopenal.dylib"

xcode-select -p >/dev/null 2>&1 || die "Xcode Command Line Tools missing: run  xcode-select --install  and try again"
[ -f "$BIN" ] || die "Frostpunk not found at: $APP
Pass the path to Frostpunk.app if your Steam library is elsewhere."
! pgrep -f 'Frostpunk.app/Contents/MacOS/Frostpunk' >/dev/null || die "Frostpunk is running, quit it first"
[ "$(lipo -archs "$BIN")" = x86_64 ] || die "unexpected game binary (not x86_64-only), not touching it"

links="$(otool -L "$BIN")"
if grep -qF "$OUR_OPENAL" <<<"$links"; then patched=1
elif grep -qF "$APPLE_OPENAL" <<<"$links"; then patched=0
else die "game binary links neither Apple OpenAL nor OpenAL Soft; unknown game version, not touching it"
fi

if [ "$undo" = 1 ]; then
  [ "$patched" = 1 ] || { echo "Game already uses Apple OpenAL, nothing to undo."; exit 0; }
  [ -f "$BAK" ] || die "no backup at $BAK; use Steam > Frostpunk > Properties > Installed Files > Verify integrity"
  cp -p "$BAK" "$BIN"
  rm -f "$DEST"
  codesign --force --sign - "$APP"
  codesign --verify --deep --strict "$APP"
  echo "Restored the original binary (Apple OpenAL). Backup kept at: $BAK"
  exit 0
fi

# The OpenAL Soft dylib: ours (checksum-verified) or your own build via FP_OPENAL_LIB.
LIB="${FP_OPENAL_LIB:-$HERE/libopenal.dylib}"
[ -f "$LIB" ] || die "dylib not found: $LIB"
if [ -z "${FP_OPENAL_LIB:-}" ]; then
  [ "$(shasum -a 256 "$LIB" | cut -d' ' -f1)" = "$LIB_SHA256" ] || die "libopenal.dylib checksum mismatch, download the repo again"
fi
[ "$(lipo -archs "$LIB")" = x86_64 ] || die "$LIB is not an x86_64 dylib"
missing="$(comm -23 <(nm -u "$BIN" | grep -E '^_al' | sort) <(nm -gU "$LIB" | awk '{print $3}' | sort))"
[ -z "$missing" ] || die "the dylib lacks OpenAL functions the game uses: $missing"

echo "Installing OpenAL Soft into the app bundle..."
cp "$LIB" "$DEST"
xattr -c "$DEST"   # drop the quarantine flag of a browser download, or Gatekeeper may block loading it
[ "$(otool -D "$DEST" | tail -1)" = "$OUR_OPENAL" ] || install_name_tool -id "$OUR_OPENAL" "$DEST"
codesign --force --sign - "$DEST"

if [ "$patched" = 0 ]; then
  echo "Backing up the game binary to $(basename "$BAK") and repointing OpenAL..."
  cp -p "$BIN" "$BAK"
  # Prints a warning that the signature becomes invalid; the app is re-signed below.
  install_name_tool -change "$APPLE_OPENAL" "$OUR_OPENAL" "$BIN"
else
  echo "Game binary already points to OpenAL Soft."
fi

# Steam ships the frameworks' symlinks as XSym text files (1067 bytes, "XSym" header, target on line 4).
# dyld doesn't mind, but codesign rejects the frameworks, so turn them back into real symlinks.
fixed=0
while IFS= read -r -d '' f; do
  [ "$(head -c 5 "$f")" = "XSym" ] || continue
  t="$(sed -n 4p "$f")"; n="$(sed -n 2p "$f")"
  [ "${#t}" -eq "$((10#$n))" ] || die "malformed XSym file: $f"
  rm "$f"; ln -s "$t" "$f"; fixed=$((fixed + 1))
done < <(find "$C/Frameworks" -type f -size 1067c -print0)
echo "Restored $fixed framework symlinks."

# Leftovers of an earlier `codesign --deep` attempt: a signature at the framework root instead of Versions/A.
for d in "$C"/Frameworks/*.framework/_CodeSignature; do
  [ -d "$d" ] && { echo "Removing stray $d"; rm -r "$d"; }
done

# Sign the app only. The frameworks keep their original signatures; --deep would re-sign them.
echo "Signing the app (ad-hoc)..."
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
otool -L "$BIN" | grep -qF "$OUR_OPENAL" || die "verification failed: binary does not link OpenAL Soft"

echo
echo "Done. Frostpunk now uses OpenAL Soft. Start it from Steam as usual."
echo "Run this script again after every Frostpunk update."
