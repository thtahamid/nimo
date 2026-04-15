# Nimo

Nimo is a macOS installer that patches Discord.app so the client can connect from networks that block Discord's voice/RTC endpoints. It installs a small dylib (`nimo.dylib`) into Discord's app bundle via `DYLD_INSERT_LIBRARIES` and interposes `sendto`/`close` to inject a short primer packet before the first real UDP payload, which is enough to traverse certain captive portals and restrictive middleboxes.

See `prd.md` for the product requirements and `macos-implementation-plan.md` for the full technical plan. The `discord-drover/` directory is the original Windows reference implementation (Delphi) used as a behavioural spec for the macOS port.

## Installation (macOS)

1. Download the latest `Nimo-<version>.dmg` from the [GitHub Releases](../../releases) page.
2. Open the DMG and drag `Nimo.app` into `/Applications`.
3. Because the build is unsigned and not notarised, Gatekeeper will block it on first launch. Right-click `Nimo.app` in Finder and choose **Open**, then confirm the prompt. After the first launch Gatekeeper remembers the decision.
4. Quit Discord, launch Nimo, click **Install**, then relaunch Discord.

Requirements:

- macOS 12 Monterey or later.
- Universal binary — runs natively on Intel and Apple Silicon.
- Discord, Discord Canary, or Discord PTB installed in `/Applications` or `~/Applications`.

## Building from source

TL;DR from the repo root on a Mac with Xcode 15+ and the prerequisites installed:

```
make build
```

See `macos/README.md` for prerequisites, full build targets, the install/uninstall flow, release process, and troubleshooting.

## Project layout

```
nimo-1/
  macos/
    dylib/              C source for nimo.dylib (Makefile + clang)
    installer/          SwiftUI installer app (Sources/ + Tests/)
    scripts/            build, package, and release shell scripts
  .github/workflows/    CI (build.yml) and release (release.yml)
  discord-drover/       Windows Delphi reference implementation
  prd.md                product requirements
  macos-implementation-plan.md
```

## License

See [LICENSE](LICENSE).
