# Nimo macOS Implementation Plan

## Overview

This document outlines the complete implementation plan for building, testing, and releasing the Nimo macOS application. The app intercepts Discord's UDP socket calls and injects primer packets to bypass network restrictions.

**Target:** macOS 12 Monterey through macOS 15 Sequoia  
**Architecture:** Universal Binary (Intel x86_64 + Apple Silicon arm64)  
**Distribution:** GitHub Releases (DMG installer)

---

## Table of Contents

1. [Phase 1: Project Setup](#phase-1-project-setup)
2. [Phase 2: Core Library Implementation](#phase-2-core-library-implementation)
3. [Phase 3: Installer Application](#phase-3-installer-application)
4. [Phase 4: Testing](#phase-4-testing)
5. [Phase 5: Build Automation](#phase-5-build-automation)
6. [Phase 6: Release Pipeline](#phase-6-release-pipeline)

---

## Phase 1: Project Setup

### Task 1.1: Initialize macOS Project Structure

**Duration:** 1 day

#### Subtasks:

- [ ] **1.1.1** Create `macos/` directory at project root
- [ ] **1.1.2** Initialize Xcode workspace for the project
- [ ] **1.1.3** Create two Xcode projects:
  - `NimoDylib` - Dynamic library for socket interposition
  - `NimoInstaller` - SwiftUI installer application
- [ ] **1.1.4** Configure shared build settings file (`Config.xcconfig`)
- [ ] **1.1.5** Add `.gitignore` entries for Xcode build artifacts

#### Directory Structure:

```
macos/
├── NimoDylib/
│   ├── NimoDylib.xcodeproj/
│   └── Sources/
│       └── nimo.c
├── NimoInstaller/
│   ├── NimoInstaller.xcodeproj/
│   └── Sources/
│       ├── NimoInstallerApp.swift
│       ├── Views/
│       ├── Models/
│       └── Utilities/
├── Shared/
│   └── Config.xcconfig
├── Scripts/
│   └── build.sh
└── Nimo.xcworkspace
```

---

### Task 1.2: Configure Code Signing

**Duration:** 0.5 day

#### Subtasks:

- [ ] **1.2.1** Create Apple Developer ID Application certificate
- [ ] **1.2.2** Create Apple Developer ID Installer certificate (for DMG notarization)
- [ ] **1.2.3** Configure Xcode projects with automatic signing for development
- [ ] **1.2.4** Document manual signing process for CI/CD
- [ ] **1.2.5** Add entitlements file for the installer app:
  - `com.apple.security.automation.apple-events` (for Discord detection)

---

### Task 1.3: Set Up Development Environment

**Duration:** 0.5 day

#### Subtasks:

- [ ] **1.3.1** Document required Xcode version (15.0+)
- [ ] **1.3.2** Create development README with setup instructions
- [ ] **1.3.3** Configure SwiftLint for code style enforcement
- [ ] **1.3.4** Set up pre-commit hooks for linting

---

## Phase 2: Core Library Implementation

### Task 2.1: Implement Socket Interposition Library

**Duration:** 3 days

#### Subtasks:

- [ ] **2.1.1** Create `nimo.c` with dyld interposing structure
- [ ] **2.1.2** Implement `sendto` interposition function
- [ ] **2.1.3** Implement socket tracking mechanism (first-send detection per file descriptor)
- [ ] **2.1.4** Implement primer packet injection logic:
  - Send 1-byte packet with value `0x00`
  - Send 1-byte packet with value `0x01`
  - Wait 50ms using `usleep(50000)`
  - Send original 74-byte packet
- [ ] **2.1.5** Add thread safety using dispatch queues or pthread mutexes
- [ ] **2.1.6** Implement socket close tracking to reset first-send state

#### Code Implementation:

```c
// nimo.c - Core interposition library

#define _GNU_SOURCE
#include <sys/socket.h>
#include <unistd.h>
#include <stdbool.h>
#include <pthread.h>
#include <stdint.h>
#include <mach-o/dyld-interposing.h>

#define MAX_SOCKETS 65536
#define HANDSHAKE_SIZE 74

static bool socket_first_send[MAX_SOCKETS];
static pthread_mutex_t socket_mutex = PTHREAD_MUTEX_INITIALIZER;

static ssize_t (*real_sendto)(int, const void *, size_t, int,
                               const struct sockaddr *, socklen_t);

// Check and mark first send for a socket
static bool is_first_send(int sockfd) {
    if (sockfd < 0 || sockfd >= MAX_SOCKETS) return false;

    pthread_mutex_lock(&socket_mutex);
    bool first = !socket_first_send[sockfd];
    if (first) socket_first_send[sockfd] = true;
    pthread_mutex_unlock(&socket_mutex);

    return first;
}

// Interposed sendto function
ssize_t nimo_sendto(int sockfd, const void *buf, size_t len, int flags,
                    const struct sockaddr *dest_addr, socklen_t addrlen) {

    if (is_first_send(sockfd) && len == HANDSHAKE_SIZE) {
        // Send primer packets
        uint8_t primer0 = 0x00;
        uint8_t primer1 = 0x01;

        real_sendto(sockfd, &primer0, 1, flags, dest_addr, addrlen);
        real_sendto(sockfd, &primer1, 1, flags, dest_addr, addrlen);

        // Wait for NAT/firewall state establishment
        usleep(50000);  // 50ms
    }

    return real_sendto(sockfd, buf, len, flags, dest_addr, addrlen);
}

// Reset tracking when socket closes
static int (*real_close)(int);

int nimo_close(int fd) {
    if (fd >= 0 && fd < MAX_SOCKETS) {
        pthread_mutex_lock(&socket_mutex);
        socket_first_send[fd] = false;
        pthread_mutex_unlock(&socket_mutex);
    }
    return real_close(fd);
}

// DYLD Interpose declarations
DYLD_INTERPOSE(nimo_sendto, sendto)
DYLD_INTERPOSE(nimo_close, close)
```

---

### Task 2.2: Build Configuration for Universal Binary

**Duration:** 0.5 day

#### Subtasks:

- [ ] **2.2.1** Configure dylib target for Universal Binary (arm64 + x86_64)
- [ ] **2.2.2** Set deployment target to macOS 12.0
- [ ] **2.2.3** Configure build settings:
  - `ARCHS = arm64 x86_64`
  - `MACOSX_DEPLOYMENT_TARGET = 12.0`
  - `DYLIB_INSTALL_NAME_BASE = @rpath`
- [ ] **2.2.4** Add version info plist for the dylib
- [ ] **2.2.5** Test compilation on both Intel and Apple Silicon Macs

---

### Task 2.3: Create Launcher Script

**Duration:** 0.5 day

#### Subtasks:

- [ ] **2.3.1** Create `discord-launcher.sh` script template:

```bash
#!/bin/bash
# Nimo Discord Launcher
# Injects nimo.dylib via DYLD_INSERT_LIBRARIES

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export DYLD_INSERT_LIBRARIES="$SCRIPT_DIR/nimo.dylib"

exec "$SCRIPT_DIR/Discord.real" "$@"
```

- [ ] **2.3.2** Ensure script handles all command-line arguments
- [ ] **2.3.3** Add error handling for missing dylib
- [ ] **2.3.4** Test script execution with Discord

---

## Phase 3: Installer Application

### Task 3.1: Create SwiftUI Installer App

**Duration:** 3 days

#### Subtasks:

- [ ] **3.1.1** Set up SwiftUI app structure with App lifecycle
- [ ] **3.1.2** Design main installer view matching PRD mockup:
  - Discord detection status
  - Discord path display
  - Mode selection (Direct mode only for v1)
  - Install/Uninstall buttons
- [ ] **3.1.3** Implement Discord detection logic:
  - Check `/Applications/Discord.app`
  - Check `~/Applications/Discord.app`
  - Support Discord Canary and PTB editions
- [ ] **3.1.4** Create model classes:
  - `DiscordInstallation` - Represents a Discord installation
  - `InstallationState` - Tracks installation status
- [ ] **3.1.5** Implement app icon and visual assets

#### View Structure:

```swift
// ContentView.swift
struct ContentView: View {
    @StateObject private var installer = InstallerViewModel()

    var body: some View {
        VStack(spacing: 20) {
            HeaderView()

            DiscordStatusView(installations: installer.installations)

            ModeSelectionView(mode: $installer.mode)

            ActionButtonsView(
                onInstall: installer.install,
                onUninstall: installer.uninstall,
                isInstalled: installer.isInstalled
            )

            StatusMessageView(message: installer.statusMessage)
        }
        .frame(width: 400, height: 300)
        .padding()
    }
}
```

---

### Task 3.2: Implement Installation Logic

**Duration:** 2 days

#### Subtasks:

- [ ] **3.2.1** Implement file operations with proper error handling:
  - Backup original Discord binary (rename to `Discord.real`)
  - Copy `nimo.dylib` to Discord MacOS folder
  - Create launcher script with correct permissions
  - Replace Discord binary symlink/wrapper
- [ ] **3.2.2** Handle file permissions:
  - Request authorization for protected directories
  - Use `NSWorkspace` authorization APIs if needed
- [ ] **3.2.3** Implement uninstall logic:
  - Remove `nimo.dylib`
  - Remove launcher script
  - Restore original Discord binary from backup
- [ ] **3.2.4** Add installation verification (check all files in place)
- [ ] **3.2.5** Handle multiple Discord editions (Stable, Canary, PTB)

#### Installation Flow:

```swift
// InstallationManager.swift
class InstallationManager {

    func install(to discordPath: URL) throws {
        let macOSPath = discordPath.appendingPathComponent("Contents/MacOS")
        let discordBinary = macOSPath.appendingPathComponent("Discord")
        let discordReal = macOSPath.appendingPathComponent("Discord.real")
        let dylib = macOSPath.appendingPathComponent("nimo.dylib")
        let launcher = macOSPath.appendingPathComponent("Discord")

        // Step 1: Backup original binary
        if !FileManager.default.fileExists(atPath: discordReal.path) {
            try FileManager.default.moveItem(at: discordBinary, to: discordReal)
        }

        // Step 2: Copy dylib from app bundle
        let bundledDylib = Bundle.main.url(forResource: "nimo", withExtension: "dylib")!
        try FileManager.default.copyItem(at: bundledDylib, to: dylib)

        // Step 3: Create launcher script
        let launcherScript = generateLauncherScript()
        try launcherScript.write(to: launcher, atomically: true, encoding: .utf8)

        // Step 4: Make launcher executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: launcher.path
        )
    }

    func uninstall(from discordPath: URL) throws {
        // Reverse the installation process
    }
}
```

---

### Task 3.3: Add Progress and Error Handling

**Duration:** 1 day

#### Subtasks:

- [ ] **3.3.1** Add progress indicators for installation/uninstallation
- [ ] **3.3.2** Implement comprehensive error handling:
  - Discord not found
  - Permission denied
  - Disk full
  - File in use
- [ ] **3.3.3** Display user-friendly error messages
- [ ] **3.3.4** Add success confirmation dialogs
- [ ] **3.3.5** Implement logging for debugging (to `~/Library/Logs/Nimo/`)

---

### Task 3.4: Bundle Resources

**Duration:** 0.5 day

#### Subtasks:

- [ ] **3.4.1** Embed pre-built `nimo.dylib` in installer app bundle
- [ ] **3.4.2** Add launcher script template as bundle resource
- [ ] **3.4.3** Configure Copy Files build phase for dylib
- [ ] **3.4.4** Verify bundle structure and code signing

---

## Phase 4: Testing

### Task 4.1: Unit Testing

**Duration:** 2 days

#### Subtasks:

- [ ] **4.1.1** Set up XCTest targets for both projects
- [ ] **4.1.2** Write unit tests for socket tracking logic:
  - Test first-send detection
  - Test socket reset on close
  - Test thread safety
- [ ] **4.1.3** Write unit tests for installation manager:
  - Test Discord detection
  - Test file operations (using temp directories)
  - Test backup/restore logic
- [ ] **4.1.4** Write unit tests for view models
- [ ] **4.1.5** Aim for 80%+ code coverage on business logic

#### Test Examples:

```swift
// SocketTrackingTests.swift
class SocketTrackingTests: XCTestCase {

    func testFirstSendDetection() {
        let tracker = SocketTracker()

        XCTAssertTrue(tracker.isFirstSend(sockfd: 5))
        XCTAssertFalse(tracker.isFirstSend(sockfd: 5))
    }

    func testSocketResetOnClose() {
        let tracker = SocketTracker()

        _ = tracker.isFirstSend(sockfd: 5)
        tracker.socketClosed(sockfd: 5)
        XCTAssertTrue(tracker.isFirstSend(sockfd: 5))
    }
}
```

---

### Task 4.2: Integration Testing

**Duration:** 2 days

#### Subtasks:

- [ ] **4.2.1** Create integration test suite:
  - Test dylib loading with test harness app
  - Test primer packet injection captures
  - Test installation end-to-end flow
- [ ] **4.2.2** Create mock Discord.app structure for testing
- [ ] **4.2.3** Test on multiple macOS versions (VM or physical):
  - macOS 12 Monterey
  - macOS 13 Ventura
  - macOS 14 Sonoma
  - macOS 15 Sequoia
- [ ] **4.2.4** Test on both architectures:
  - Apple Silicon (arm64)
  - Intel (x86_64) via Rosetta 2
- [ ] **4.2.5** Document test results matrix

---

### Task 4.3: Manual Testing Checklist

**Duration:** 1 day

#### Subtasks:

- [ ] **4.3.1** Create manual test checklist document
- [ ] **4.3.2** Test scenarios:
  - Fresh install on clean system
  - Install over previous version
  - Uninstall and reinstall
  - Discord auto-update behavior
  - Install with Discord running (should prompt to quit)
- [ ] **4.3.3** Test Discord functionality after installation:
  - Text chat works
  - Voice chat works
  - Video chat works
  - Screen share works
- [ ] **4.3.4** Test in restricted network environment (if available):
  - UAE ISP simulation
  - Corporate firewall simulation
- [ ] **4.3.5** Test uninstall restores Discord to original state

---

### Task 4.4: Performance Testing

**Duration:** 0.5 day

#### Subtasks:

- [ ] **4.4.1** Measure memory overhead of injected dylib (target: < 5MB)
- [ ] **4.4.2** Measure CPU impact during voice calls (target: negligible)
- [ ] **4.4.3** Verify 50ms delay on first voice connection only
- [ ] **4.4.4** Test long-running Discord sessions (8+ hours)
- [ ] **4.4.5** Document performance test results

---

## Phase 5: Build Automation

### Task 5.1: Create Build Scripts

**Duration:** 1 day

#### Subtasks:

- [ ] **5.1.1** Create `scripts/build.sh` for local builds:

```bash
#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Build dylib (Universal Binary)
xcodebuild -project "$PROJECT_DIR/NimoDylib/NimoDylib.xcodeproj" \
    -scheme NimoDylib \
    -configuration Release \
    -arch arm64 -arch x86_64 \
    ONLY_ACTIVE_ARCH=NO \
    BUILD_DIR="$PROJECT_DIR/build"

# Build installer app
xcodebuild -project "$PROJECT_DIR/NimoInstaller/NimoInstaller.xcodeproj" \
    -scheme NimoInstaller \
    -configuration Release \
    -arch arm64 -arch x86_64 \
    ONLY_ACTIVE_ARCH=NO \
    BUILD_DIR="$PROJECT_DIR/build"

echo "Build complete: $PROJECT_DIR/build/Release"
```

- [ ] **5.1.2** Create `scripts/create-dmg.sh` for DMG creation:

```bash
#!/bin/bash
set -e

VERSION="${1:-1.0.0}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/Release"
DMG_DIR="$PROJECT_DIR/build/dmg"

mkdir -p "$DMG_DIR"

# Create DMG
create-dmg \
    --volname "Nimo Installer" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "Nimo.app" 150 190 \
    --app-drop-link 450 185 \
    --hide-extension "Nimo.app" \
    "$DMG_DIR/Nimo-$VERSION.dmg" \
    "$BUILD_DIR/Nimo.app"
```

- [ ] **5.1.3** Create `scripts/sign.sh` for code signing
- [ ] **5.1.4** Create `scripts/notarize.sh` for Apple notarization
- [ ] **5.1.5** Add `Makefile` for convenient build commands

---

### Task 5.2: Set Up GitHub Actions CI

**Duration:** 1.5 days

#### Subtasks:

- [ ] **5.2.1** Create `.github/workflows/build.yml`:

```yaml
name: Build macOS

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-14

    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.2.app

      - name: Build Dylib
        run: |
          xcodebuild -project macos/NimoDylib/NimoDylib.xcodeproj \
            -scheme NimoDylib \
            -configuration Release \
            -arch arm64 -arch x86_64 \
            ONLY_ACTIVE_ARCH=NO

      - name: Build Installer
        run: |
          xcodebuild -project macos/NimoInstaller/NimoInstaller.xcodeproj \
            -scheme NimoInstaller \
            -configuration Release \
            -arch arm64 -arch x86_64 \
            ONLY_ACTIVE_ARCH=NO

      - name: Run Tests
        run: |
          xcodebuild test -project macos/NimoInstaller/NimoInstaller.xcodeproj \
            -scheme NimoInstaller \
            -destination 'platform=macOS'

      - name: Upload Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: nimo-macos-build
          path: |
            build/Release/Nimo.app
            build/Release/nimo.dylib
```

- [ ] **5.2.2** Create `.github/workflows/test.yml` for running tests on PRs
- [ ] **5.2.3** Add build status badge to README
- [ ] **5.2.4** Configure test reporting and coverage

---

### Task 5.3: Set Up Code Signing in CI

**Duration:** 1 day

#### Subtasks:

- [ ] **5.3.1** Store signing certificates as GitHub Secrets:
  - `MACOS_CERTIFICATE` - Base64 encoded p12 file
  - `MACOS_CERTIFICATE_PWD` - Certificate password
  - `KEYCHAIN_PWD` - Temporary keychain password
- [ ] **5.3.2** Store Apple ID credentials for notarization:
  - `APPLE_ID`
  - `APPLE_APP_SPECIFIC_PASSWORD`
  - `APPLE_TEAM_ID`
- [ ] **5.3.3** Add signing step to GitHub Actions workflow:

```yaml
- name: Install Certificates
  env:
    MACOS_CERTIFICATE: ${{ secrets.MACOS_CERTIFICATE }}
    MACOS_CERTIFICATE_PWD: ${{ secrets.MACOS_CERTIFICATE_PWD }}
  run: |
    echo $MACOS_CERTIFICATE | base64 --decode > certificate.p12
    security create-keychain -p "$KEYCHAIN_PWD" build.keychain
    security import certificate.p12 -k build.keychain -P "$MACOS_CERTIFICATE_PWD" -T /usr/bin/codesign
    security list-keychains -s build.keychain
    security set-keychain-settings build.keychain
    security unlock-keychain -p "$KEYCHAIN_PWD" build.keychain
```

- [ ] **5.3.4** Add notarization step to workflow
- [ ] **5.3.5** Test signed builds on fresh macOS installation

---

## Phase 6: Release Pipeline

### Task 6.1: Version Management

**Duration:** 0.5 day

#### Subtasks:

- [ ] **6.1.1** Define versioning strategy (Semantic Versioning):
  - `MAJOR.MINOR.PATCH` (e.g., 1.0.0)
  - Update Info.plist on each release
- [ ] **6.1.2** Create `scripts/bump-version.sh`:

```bash
#!/bin/bash
VERSION=$1
# Update Info.plist files
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
    macos/NimoInstaller/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" \
    macos/NimoInstaller/Info.plist
```

- [ ] **6.1.3** Document version update process
- [ ] **6.1.4** Add CHANGELOG.md for tracking releases

---

### Task 6.2: Create Release Workflow

**Duration:** 1 day

#### Subtasks:

- [ ] **6.2.1** Create `.github/workflows/release.yml`:

```yaml
name: Release macOS

on:
  push:
    tags:
      - "v*"

jobs:
  release:
    runs-on: macos-14

    steps:
      - uses: actions/checkout@v4

      - name: Get Version
        id: version
        run: echo "VERSION=${GITHUB_REF#refs/tags/v}" >> $GITHUB_OUTPUT

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.2.app

      - name: Install create-dmg
        run: brew install create-dmg

      - name: Install Certificates
        env:
          MACOS_CERTIFICATE: ${{ secrets.MACOS_CERTIFICATE }}
          MACOS_CERTIFICATE_PWD: ${{ secrets.MACOS_CERTIFICATE_PWD }}
          KEYCHAIN_PWD: ${{ secrets.KEYCHAIN_PWD }}
        run: |
          # Certificate installation steps...

      - name: Build Release
        run: |
          ./macos/scripts/build.sh

      - name: Sign Application
        run: |
          codesign --deep --force --verify --verbose \
            --sign "Developer ID Application: Your Name (TEAM_ID)" \
            build/Release/Nimo.app

      - name: Create DMG
        run: |
          ./macos/scripts/create-dmg.sh ${{ steps.version.outputs.VERSION }}

      - name: Sign DMG
        run: |
          codesign --sign "Developer ID Application: Your Name (TEAM_ID)" \
            build/dmg/Nimo-${{ steps.version.outputs.VERSION }}.dmg

      - name: Notarize DMG
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          xcrun notarytool submit build/dmg/Nimo-*.dmg \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_APP_SPECIFIC_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            --wait
          xcrun stapler staple build/dmg/Nimo-*.dmg

      - name: Create Checksums
        run: |
          cd build/dmg
          shasum -a 256 *.dmg > checksums.txt

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            build/dmg/Nimo-*.dmg
            build/dmg/checksums.txt
          body: |
            ## Nimo ${{ steps.version.outputs.VERSION }} for macOS

            ### Installation
            1. Download `Nimo-${{ steps.version.outputs.VERSION }}.dmg`
            2. Open the DMG and drag Nimo to Applications
            3. Run Nimo and click Install

            ### Requirements
            - macOS 12 Monterey or later
            - Discord (Stable, Canary, or PTB)

            ### Checksums
            See `checksums.txt` for SHA-256 hashes.
          draft: false
          prerelease: false
```

- [ ] **6.2.2** Add release notes template
- [ ] **6.2.3** Configure GitHub Release settings (auto-generate notes)
- [ ] **6.2.4** Test release workflow with pre-release tag

---

### Task 6.3: Documentation for Releases

**Duration:** 0.5 day

#### Subtasks:

- [ ] **6.3.1** Create release checklist:

```markdown
## Release Checklist

- [ ] All tests passing on main branch
- [ ] Version bumped in Info.plist files
- [ ] CHANGELOG.md updated
- [ ] README.md updated if needed
- [ ] Create and push tag: `git tag v1.0.0 && git push origin v1.0.0`
- [ ] Verify GitHub Actions workflow runs successfully
- [ ] Verify DMG downloads and installs correctly
- [ ] Verify notarization status with Gatekeeper
- [ ] Announce release (if applicable)
```

- [ ] **6.3.2** Update main README with:
  - Installation instructions
  - Download link to latest release
  - macOS version requirements
- [ ] **6.3.3** Create troubleshooting guide for common issues
- [ ] **6.3.4** Document SIP/Gatekeeper considerations

---

### Task 6.4: Post-Release Verification

**Duration:** 0.5 day

#### Subtasks:

- [ ] **6.4.1** Download released DMG from GitHub
- [ ] **6.4.2** Verify Gatekeeper approval (no "unidentified developer" warning)
- [ ] **6.4.3** Test installation on fresh macOS system
- [ ] **6.4.4** Verify Discord voice works with Nimo installed
- [ ] **6.4.5** Check for any crash reports or issues

---

## Timeline Summary

| Phase                     | Duration     | Start  | End    |
| ------------------------- | ------------ | ------ | ------ |
| Phase 1: Project Setup    | 2 days       | Day 1  | Day 2  |
| Phase 2: Core Library     | 4 days       | Day 3  | Day 6  |
| Phase 3: Installer App    | 6.5 days     | Day 7  | Day 13 |
| Phase 4: Testing          | 5.5 days     | Day 14 | Day 19 |
| Phase 5: Build Automation | 3.5 days     | Day 20 | Day 23 |
| Phase 6: Release Pipeline | 2.5 days     | Day 24 | Day 26 |
| **Total**                 | **~5 weeks** |        |        |

---

## Dependencies and Prerequisites

### Required Tools

- Xcode 15.0+
- create-dmg (`brew install create-dmg`)
- SwiftLint (`brew install swiftlint`)
- xcpretty (optional, for CI output formatting)

### Required Accounts

- Apple Developer Program membership ($99/year)
- GitHub repository with Actions enabled

### Required Certificates

- Developer ID Application certificate
- Developer ID Installer certificate (if using pkg)

---

## Risk Mitigation

| Risk                                         | Mitigation                                               |
| -------------------------------------------- | -------------------------------------------------------- |
| Apple changes DYLD_INSERT_LIBRARIES behavior | Monitor macOS betas; have fallback approaches documented |
| Discord updates break installation           | Version detection; handle multiple Discord versions      |
| Notarization failures                        | Test notarization early; maintain valid certificates     |
| CI runner macOS version lag                  | Pin specific Xcode/macOS versions; test locally first    |

---

## Success Criteria

1. ✅ Universal binary runs on both Intel and Apple Silicon Macs
2. ✅ Installer successfully installs/uninstalls on all supported macOS versions
3. ✅ Discord voice chat works in restricted network environments
4. ✅ DMG is properly signed and notarized (no Gatekeeper warnings)
5. ✅ GitHub Actions successfully builds and releases on tag push
6. ✅ All unit and integration tests pass
7. ✅ Memory usage under 5MB, negligible CPU impact

---

_Document Version: 1.0_  
_Last Updated: February 6, 2026_
