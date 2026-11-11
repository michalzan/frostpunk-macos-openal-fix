# Frostpunk macOS OpenAL fix

Fixes Frostpunk (Steam, macOS) crashing when you load a save, **with sound**. The usual workaround is
the `-nosound` launch option, which avoids the crash by muting the game.

## Symptoms

- macOS 26 (Tahoe) on Apple Silicon. Frostpunk is Intel-only and runs under Rosetta 2.
- Menus work, but loading a save or a large city crashes the game.
- The crash report shows `EXC_BAD_INSTRUCTION (SIGILL)` on the `SoundEngine` thread, inside
  `OpenAL` → `AudioToolbox` (`AudioConverterNew` / `AudioConverterDispose`) → `caulk`.

The crash is in Apple's own OpenAL running under Rosetta, not in the game's code. This repo swaps
in [OpenAL Soft](https://github.com/kcat/openal-soft), an independent OpenAL implementation, and
the game sound works normally with it. Other Intel games hit the same bug and were fixed the same way, e.g.
[ToME 4](https://forums.te4.org/viewtopic.php?p=251795).

## Install

1. Quit Frostpunk.
2. Install Apple's command line tools if you don't have them: `xcode-select --install`
3. In Terminal:

```bash
git clone https://github.com/michalzan/frostpunk-macos-openal-fix.git
cd frostpunk-macos-openal-fix
bash fix.sh
```

4. Start Frostpunk from Steam as usual.

Without git: **Code → Download ZIP** on GitHub, unzip, then `cd` into the folder and run `bash fix.sh`.

If your Steam library is not in the default place, pass the app path:

```bash
bash fix.sh "/Volumes/Games/SteamLibrary/steamapps/common/Frostpunk/Frostpunk.app"
```

**Run the script again after every Frostpunk update.** An update replaces the game binary and undoes the fix.

## What the script does

Only files inside `Frostpunk.app` are changed:

1. Checks that this is the expected game binary (x86_64, links Apple's OpenAL), that the bundled
   `libopenal.dylib` matches its SHA-256, and that it provides every OpenAL function the game uses.
2. Copies `libopenal.dylib` into `Frostpunk.app/Contents/Frameworks/`.
3. Backs up the game binary to `Contents/MacOS/Frostpunk.apple-openal.bak` and changes its OpenAL
   reference from `/System/Library/Frameworks/OpenAL.framework` to the bundled library
   (`install_name_tool -change`).
4. Repairs the frameworks' symlinks. Steam installs them as small "XSym" text files, which makes
   `codesign` reject the app ("embedded framework contains modified or invalid version").
5. Re-signs the app ad-hoc (`codesign --sign -`), without `--deep`, so the bundled frameworks keep
   their original signatures, then verifies the signature.

## Undo

```bash
bash fix.sh --undo
```

Or in Steam: Frostpunk → Properties → Installed Files → **Verify integrity of game files**.

## Build OpenAL Soft yourself

The bundled `libopenal.dylib` is OpenAL Soft 1.25.2 (upstream commit `b2c48f7`), built for x86_64
with no changes to the source. If you'd rather not run a binary from the internet, build it yourself
(needs `cmake`, e.g. `brew install cmake`):

```bash
git clone --depth 1 --branch 1.25.2 https://github.com/kcat/openal-soft.git
cmake -S openal-soft -B openal-soft/build -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF -DALSOFT_INSTALL=OFF \
  -DHAVE_WFUNCTION_EFFECTS=OFF     # needed to compile against the macOS 26 SDK
cmake --build openal-soft/build -j
FP_OPENAL_LIB="$PWD/openal-soft/build/libopenal.1.25.2.dylib" bash fix.sh
```

With `FP_OPENAL_LIB` set, the checksum check is skipped. The architecture and symbol checks still run.

## Tested on

| | |
|---|---|
| Mac | MacBook Pro M4 Pro |
| macOS | 26.4.1 (25E253) |
| Frostpunk | 1.1.1 (20201216.0), Steam |

Result: the save that used to crash loads, sound plays, and the game runs from Steam. Other setups
are untested. If it works for you, or doesn't, please open an issue with your Mac, macOS and game version.

## License

- `fix.sh`: MIT, see `LICENSE`.
- `libopenal.dylib`: OpenAL Soft, GNU LGPL v2, see `licenses/openal-soft/COPYING` (and
  `LICENSE-pffft` for the bundled PFFFT code). Source: https://github.com/kcat/openal-soft at tag `1.25.2`.

Not affiliated with 11 bit studios or Valve.
