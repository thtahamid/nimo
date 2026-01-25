# Nimo - Product Requirements Document

## Overview

**Product Name:** Nimo  
**Version:** 1.0 (Draft)  
**Last Updated:** January 25, 2026

Nimo is a lightweight desktop utility that enables Discord voice and video chat to bypass network restrictions on Windows and macOS. It replicates the **"Direct" mode** functionality from the open-source [discord-drover](discord-drover/) project, using UDP packet manipulation to enable voice chat in restricted network environments—without requiring a proxy server.

---

## Problem Statement

Users in certain regions (e.g., UAE) and network environments experience blocked or degraded Discord voice/video chat due to:

- ISP-level blocking of Discord's voice protocol
- Deep packet inspection (DPI) detecting and throttling Discord UDP traffic
- Network policies that allow Discord text chat but block voice/video
- Firewalls that restrict the initial UDP handshake packets

---

## Target Users

1. **Users in restricted regions** where Discord voice is blocked but text works (e.g., UAE, some corporate networks)
2. **Students** in educational institutions with voice chat restrictions
3. **Corporate users** behind restrictive firewalls that block UDP-based voice
4. **Anyone** needing Discord voice to work without configuring a full proxy/VPN

---

## Goals

- **Primary:** Enable Discord voice/video to bypass network restrictions using UDP manipulation (Direct mode)
- **Secondary:** Provide simple one-click installation for non-technical users
- **Tertiary:** Support both Windows and macOS with platform-native implementations

---

## Solution Overview

Nimo works by intercepting Discord's UDP socket calls and modifying the initial voice connection handshake. Based on the reference implementation in [discord-drover](discord-drover/), the technique is:

### Core Mechanism (Direct Mode)

When Discord initiates a voice connection, it sends a **74-byte UDP handshake packet**. Nimo intercepts this and:

1. **Sends a 1-byte "primer" packet** with value `0x00` to the same destination
2. **Sends a 1-byte "primer" packet** with value `0x01` to the same destination
3. **Waits 50ms** for the primers to establish NAT/firewall state
4. **Sends the original 74-byte packet** as normal

This "priming" technique helps bypass certain DPI systems and NAT configurations that would otherwise block the voice connection.

```
Normal Discord Flow:          Nimo Direct Mode:

Discord ──[74B]──▶ Server     Discord ──[1B: 0x00]──▶ Server
                                      ──[1B: 0x01]──▶ Server
                                      ──[50ms wait]──
                                      ──[74B]──────▶ Server
```

---

## Features

### Core Features (MVP)

| Feature                          | Description                                                                     | Priority |
| -------------------------------- | ------------------------------------------------------------------------------- | -------- |
| **UDP Primer Injection**         | Intercept first UDP send and inject primer packets before the 74-byte handshake | P0       |
| **Socket API Hooking (Windows)** | Hook `WSASendTo` via DLL injection using version.dll proxy technique            | P0       |
| **Socket API Hooking (macOS)**   | Hook socket APIs via DYLD_INSERT_LIBRARIES or similar injection                 | P0       |
| **Simple Installer**             | One-click install that places files in correct Discord folder                   | P0       |
| **Uninstaller**                  | Clean removal of all injected files                                             | P0       |
| **Discord Version Support**      | Support Discord Stable, Canary, and PTB editions                                | P1       |

### Out of Scope (v1.0)

| Feature                     | Reason                                           |
| --------------------------- | ------------------------------------------------ |
| Proxy support (HTTP/SOCKS5) | Focus only on Direct mode; proxy adds complexity |
| System tray UI              | Keep minimal; just installer/uninstaller         |
| Auto-update                 | Manual updates initially                         |
| Connection statistics       | Not needed for core functionality                |

---

## Technical Architecture

### Windows Implementation

Based on the reference [drover.dpr](discord-drover/drover.dpr):

#### DLL Proxy Technique

- Create `version.dll` that proxies all exports to the real `C:\Windows\System32\version.dll`
- Discord loads our DLL automatically when placed in its `app-*` folder
- No admin rights required for installation

#### Socket Hooking

Using [DDetours](discord-drover/DDetours.pas) library to intercept:

```pascal
// Key hooks required:
RealSocket := InterceptCreate(@socket, @MySocket, nil);
RealWSASocket := InterceptCreate(@WSASocket, @MyWSASocket, nil);
RealWSASendTo := InterceptCreate(@WSASendTo, @MyWSASendTo, nil);
```

#### UDP Manipulation Logic

```pascal
// From drover.dpr - MyWSASendTo function
if sockManager.IsFirstSend(sock, sockManagerItem) then
begin
  if sockManagerItem.isUdp and (lpBuffers.len = 74) then
  begin
    payload := 0;
    sendto(sock, pointer(@payload)^, 1, 0, @lpTo, iTolen);  // Primer 1
    payload := 1;
    sendto(sock, pointer(@payload)^, 1, 0, @lpTo, iTolen);  // Primer 2
    Sleep(50);  // Wait for NAT/firewall state
  end;
end;
```

#### Files to Deploy (Windows)

| File          | Location                            | Purpose                                   |
| ------------- | ----------------------------------- | ----------------------------------------- |
| `version.dll` | `%LocalAppData%\Discord\app-X.X.X\` | DLL proxy with hooks                      |
| `nimo.ini`    | `%LocalAppData%\Discord\app-X.X.X\` | Configuration (empty proxy = Direct mode) |

### macOS Implementation

#### Injection Technique Options

| Method                        | Pros                                 | Cons                                         |
| ----------------------------- | ------------------------------------ | -------------------------------------------- |
| **DYLD_INSERT_LIBRARIES**     | Simple, no code signing issues       | Requires launcher script or app modification |
| **Code injection via ptrace** | Works with SIP enabled               | Complex, potential security flags            |
| **Network Extension**         | Apple-approved, App Store compatible | Requires entitlements, more complex          |

**Recommended approach:** DYLD_INSERT_LIBRARIES with a launcher app

#### macOS Dylib Implementation

```c
// nimo.dylib - Interpose sendto()
#include <sys/socket.h>
#include <unistd.h>

static ssize_t (*real_sendto)(int, const void *, size_t, int,
                               const struct sockaddr *, socklen_t);

ssize_t sendto(int sockfd, const void *buf, size_t len, int flags,
               const struct sockaddr *dest_addr, socklen_t addrlen) {
    static bool first_send[FD_SETSIZE] = {false};

    if (!first_send[sockfd] && len == 74) {
        first_send[sockfd] = true;

        // Send primer packets
        uint8_t primer0 = 0x00;
        uint8_t primer1 = 0x01;
        real_sendto(sockfd, &primer0, 1, flags, dest_addr, addrlen);
        real_sendto(sockfd, &primer1, 1, flags, dest_addr, addrlen);
        usleep(50000);  // 50ms
    }

    return real_sendto(sockfd, buf, len, flags, dest_addr, addrlen);
}

// Use dyld interposing
DYLD_INTERPOSE(sendto, real_sendto)
```

#### Files to Deploy (macOS)

| File               | Location                                    | Purpose                   |
| ------------------ | ------------------------------------------- | ------------------------- |
| `nimo.dylib`       | `/Applications/Discord.app/Contents/MacOS/` | Interposed library        |
| `Discord.sh`       | `/Applications/Discord.app/Contents/MacOS/` | Launcher with DYLD_INSERT |
| Original `Discord` | Renamed to `Discord.real`                   | Preserved original binary |

---

## Installation Flow

### Windows Installer

```
┌─────────────────────────────────────────┐
│            Nimo Installer               │
├─────────────────────────────────────────┤
│                                         │
│  Discord Installation: ✓ Detected       │
│  Path: %LocalAppData%\Discord\app-1.0.x │
│                                         │
│  Mode: ○ Direct (No Proxy)              │
│                                         │
│  [Install]              [Uninstall]     │
│                                         │
└─────────────────────────────────────────┘
```

1. Detect Discord installation path(s)
2. Copy `version.dll` and `nimo.ini` to each `app-*` folder
3. Create `nimo.ini` with empty proxy (Direct mode)

### macOS Installer

```
┌─────────────────────────────────────────┐
│            Nimo Installer               │
├─────────────────────────────────────────┤
│                                         │
│  Discord App: ✓ Found                   │
│  Path: /Applications/Discord.app        │
│                                         │
│  Mode: ○ Direct (No Proxy)              │
│                                         │
│  [Install]              [Uninstall]     │
│                                         │
└─────────────────────────────────────────┘
```

1. Backup original Discord binary
2. Install `nimo.dylib`
3. Create launcher script with DYLD_INSERT_LIBRARIES

---

## Non-Functional Requirements

### Performance

- **Memory Usage:** < 5 MB additional RAM (injected DLL/dylib only)
- **CPU Usage:** Negligible (intercepts only first UDP packet per socket)
- **Latency Impact:** +50ms on initial voice connection only

### Security

- No network traffic inspection beyond packet size detection (74 bytes)
- No data collection or telemetry
- Code signing for Windows DLL and macOS dylib
- Open source for transparency

### Compatibility

| Platform | Supported Versions                         |
| -------- | ------------------------------------------ |
| Windows  | Windows 10 (1903+), Windows 11             |
| macOS    | macOS 12 Monterey through macOS 15 Sequoia |
| Discord  | Stable, Canary, PTB editions               |

---

## Risk Assessment

| Risk                                    | Impact | Likelihood | Mitigation                                            |
| --------------------------------------- | ------ | ---------- | ----------------------------------------------------- |
| Discord updates break DLL loading       | High   | Medium     | Monitor Discord releases; version.dll proxy is stable |
| macOS SIP blocks dylib injection        | High   | Low        | Use approved launcher technique; document workarounds |
| Antivirus flags version.dll             | Medium | Medium     | Code signing; submit for AV vendor allowlisting       |
| Discord changes handshake size          | High   | Low        | Make packet size configurable in nimo.ini             |
| Network changes defeat primer technique | Medium | Low        | Community testing; alternative primer sequences       |

---

## Development Timeline

| Phase                | Duration    | Deliverables                                              |
| -------------------- | ----------- | --------------------------------------------------------- |
| Windows Port         | 1 week      | Recompile/adapt existing Delphi code or rewrite in C/C++  |
| macOS Implementation | 2 weeks     | dylib with sendto interpose, launcher script              |
| Installer UI         | 1 week      | Simple installer for both platforms                       |
| Testing              | 1 week      | Test in UAE, corporate networks, various Discord versions |
| **Total**            | **5 weeks** |                                                           |

---

## Implementation Reference

The complete reference implementation is available in [discord-drover/](discord-drover/):

| File                                                  | Purpose                                            |
| ----------------------------------------------------- | -------------------------------------------------- |
| [drover.dpr](discord-drover/drover.dpr)               | Main DLL source with socket hooks                  |
| [SocketManager.pas](discord-drover/SocketManager.pas) | Tracks socket state for first-send detection       |
| [Options.pas](discord-drover/Options.pas)             | INI file parsing (proxy field empty = Direct mode) |
| [DDetours.pas](discord-drover/DDetours.pas)           | Windows API hooking library                        |
| [drover.ini](discord-drover/drover.ini)               | Configuration file template                        |

### Key Code Reference (Direct Mode Logic)

From [drover.dpr](discord-drover/drover.dpr#L195-L210):

```pascal
function MyWSASendTo(...): integer; stdcall;
var
  payload: byte;
  sockManagerItem: TSocketManagerItem;
begin
  if sockManager.IsFirstSend(sock, sockManagerItem) then
  begin
    if sockManagerItem.isUdp and (lpBuffers.len = 74) then
    begin
      payload := 0;
      sendto(sock, pointer(@payload)^, 1, 0, @lpTo, iTolen);
      payload := 1;
      sendto(sock, pointer(@payload)^, 1, 0, @lpTo, iTolen);
      Sleep(50);
    end;
  end;
  result := RealWSASendTo(...);
end;
```

---

## Open Questions

1. Should we rewrite Windows implementation in C/C++ for easier maintenance, or use existing Delphi code?
2. For macOS, is App Store distribution a goal? (Affects implementation approach)
3. Should the 50ms delay and primer packet values be configurable?

---

_This document is based on analysis of the [discord-drover](discord-drover/) open-source project. The goal is to replicate only the "Direct" mode functionality for both Windows and macOS._
