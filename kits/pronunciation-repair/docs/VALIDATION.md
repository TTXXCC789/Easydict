# Validation record — 2026-10-29

## Existing installation and real use

- App: Easydict 2.23.0, build 66.
- Environment: macOS 26.2, Apple Silicon (arm64).
- Universal Objective-C patch compilation: passed (arm64 and x86_64).
- Task-only phonetic-entry code review: no concrete findings.
- Installed application signature verification: passed.
- Startup logs confirmed the phonetic entry-point swizzle loaded.
- US and UK `sixth` files downloaded and recognized by `afinfo` as valid MP3 audio (about 1.56 / 1.51 seconds).
- Replacing the stale Accessibility row produced a saved code requirement matching the installed app, after the user completed system authentication.
- Actual selection of `stale` in the user's chat app triggered `auto_select_query` and opened the dictionary at 17:52:23 China time. Automatic speech reached native playback. US and UK phonetic playback reached native local audio at 17:52:26 and 17:52:28.
- The user confirmed the selection button appeared and subsequently reported that the modified app works.

## Kit release checks

The kit preserves the runtime source used for the successful repair. Its deployment tools were subsequently prepared for sharing.

- Python compilation and `bash -n Install.command`: passed.
- Static `doctor` on the installed app: passed; the live app was not modified by kit validation.
- New injector preflight on an original 2.23.0 executable: both architecture slices accepted.
- Complete kit installation on a disposable copy of the original 2.23.0 app: passed; staged universal compilation, injection, signing, backup, replacement and doctor all completed.
- Repeated install: passed, with exactly one patch load command in each architecture.
- Restore: passed; restored executable SHA-256 matched the original, added patch library was absent, and the replaced patched copy was separately backed up.
- Unsupported 2.23.1 metadata: refused before the installed executable changed.
- Nonempty header padding in a synthetic damaged copy: refused before file write. Reapplying the injector to already patched bytes produced no changes.
- Read-only deployment script and documentation review: no blocking findings for the supported path.
- Real abrupt power loss, filesystem faults, concurrent updater races and Intel runtime behavior were not reproduced.
- Relative Markdown links and final package checksums are checked during packaging. No personal preferences, logs, system permissions database, or full application bundle are included.

## Limits

- No full application `xcodebuild build/test` was run: this Mac has Command Line Tools, not the full Xcode installation.
- x86_64 is a compiled architecture; runtime behavior on an Intel Mac is not verified.
- Other Easydict versions, macOS versions, languages, TTS providers, application selection strategies, and all cancellation races were not exhaustively tested.
- Playback logs show the native player was invoked. Hardware audibility is a separate user check; the reported working result is the user's actual feedback.
- `codesign --verify` validates the on-disk signature; it does not establish Apple notarization or Accessibility trust.
