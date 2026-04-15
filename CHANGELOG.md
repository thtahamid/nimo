# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial macOS implementation: C dylib (`nimo.dylib`) interposing `sendto`/`close` via DYLD, SwiftUI installer app (`Nimo.app`), GitHub Actions CI/release pipeline producing unsigned DMGs.
- Support for Discord Stable, Canary, and PTB on macOS 12+ (universal binary: arm64 + x86_64).
