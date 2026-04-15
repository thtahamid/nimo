# Nimo — macOS

Developer documentation for building and working on the macOS port.

## Prerequisites

- macOS 12 (Monterey) or later.
- Xcode 15 or later, with Command Line Tools installed (`xcode-select --install`).
- Homebrew.
- The following Homebrew packages:

```
brew install xcodegen create-dmg
```

## Project layout

```
macos/
  dylib/              C source for nimo.dylib; built via Makefile + clang.
                      Produces a universal (arm64 + x86_64) dylib and hosts
                      the C unit tests for the interposer logic.
  installer/
    Sources/          SwiftUI installer app sources (Nimo.app).
    Tests/            XCTest unit/integration tests for the installer.
    project.yml       XcodeGen spec; the .xcodeproj is generated, not committed.
  scripts/            Shell scripts invoked by the root Makefile: build-dylib,
                      generate-project, build-app, package-dmg, bump-version.
```

Other relevant paths (from the repo root):

- `Makefile` — top-level entry point for all build targets.
- `.github/workflows/build.yml` — CI build and test on every push/PR.
- `.github/workflows/release.yml` — tag-triggered release that publishes the DMG.

## First-time setup

```
git clone <repo-url>
cd nimo-1
make build
```

`make build` runs the full pipeline: builds the dylib, invokes xcodegen to produce the Xcode project from `project.yml`, then runs xcodebuild to produce `Nimo.app` with `nimo.dylib` embedded as a resource.

## Build targets

Run from the repo root.

| Target | Description |
| --- | --- |
| `make dylib` | Build `nimo.dylib` as a universal binary (arm64 + x86_64). |
| `make dylib-test` | Build and run the C unit tests for the dylib. |
| `make generate` | Generate `macos/installer/NimoInstaller.xcodeproj` from `project.yml`. |
| `make build` | Full build: dylib + xcodegen + xcodebuild → `Nimo.app`. |
| `make test` | Run the full test suite (dylib C tests + installer XCTests). |
| `make dmg VERSION=1.0.0` | Package the built app into `build/dmg/Nimo-1.0.0.dmg`. |
| `make bump VERSION=1.0.0` | Bump the version string in all Info.plists and `project.yml`. |
| `make clean` | Remove `build/` artifacts and the generated `.xcodeproj`. |

## How it works

Discord on macOS uses a QUIC-like UDP transport for voice and RTC. Some restrictive networks drop the first UDP payload to Discord's servers, which kills the connection. Nimo ships a small dylib that uses DYLD interposing to wrap `sendto` and `close`: on the first outgoing UDP packet to a given socket, it sends a short "primer" packet that nudges the middlebox into letting the real traffic through, then the normal payload follows. `close` is wrapped so the per-socket state is cleaned up. The installer edits Discord's app bundle to load this dylib at launch via `DYLD_INSERT_LIBRARIES`. See `prd.md` for background and `macos-implementation-plan.md` for the detailed design.

## Install and uninstall flow

The installer targets Discord.app bundles found in `/Applications` and `~/Applications`. Supported editions: **Discord**, **Discord Canary**, and **Discord PTB**.

For each bundle found, the installer operates on `Discord.app/Contents/MacOS/`:

### Install

1. Rename the existing binary: `Discord` → `Discord.real`.
2. Copy `nimo.dylib` into `Contents/MacOS/`.
3. Write a new `Discord` launcher script (`launcher.sh`) that sets `DYLD_INSERT_LIBRARIES` to the sibling `nimo.dylib` and execs `Discord.real`. The launcher is `chmod 755`.

### Uninstall

The reverse:

1. Remove `nimo.dylib` from `Contents/MacOS/`.
2. Remove the launcher script at `Contents/MacOS/Discord`.
3. Rename `Discord.real` → `Discord`.

The installer detects an already-patched bundle by the presence of `Discord.real` and offers uninstall/reinstall accordingly.

## Release process

Releases are cut from git tags matching `v*`.

```
make bump VERSION=1.0.0
git commit -am "Release v1.0.0"
git tag v1.0.0
git push origin main v1.0.0
```

Pushing the tag triggers `.github/workflows/release.yml`, which builds on a macOS runner, produces `Nimo-1.0.0.dmg`, and attaches it to a GitHub Release for the tag.

The DMG is **unsigned** — there is no Apple Developer account associated with this project. Users will hit Gatekeeper on first launch and must right-click `Nimo.app` → **Open** to allow it. Call this out in release notes.

## Troubleshooting

**`xcodegen: command not found`** — Run `brew install xcodegen`.

**`nimo.dylib not found` during xcodebuild** — The installer build expects the dylib to be present before xcodebuild runs. Run `make dylib` first, or just use `make build`, which chains them.

**Gatekeeper blocks the DMG or the app** — Right-click `Nimo.app` → **Open**, confirm the dialog. To clear the quarantine attribute from the command line:

```
xattr -dr com.apple.quarantine /Applications/Nimo.app
```

**Discord auto-updated and the patch is gone** — This is a known limitation. Discord replaces `Contents/MacOS/Discord` as part of its auto-update, which wipes the launcher script and detaches the dylib. Re-run the installer after Discord updates itself.
