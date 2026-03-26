# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

## [Unreleased]

### Added
- Security policy in `SECURITY.md`.
- Explicit dependency manifest in `cpanfile`.
- Tag-based release workflow with checksums and provenance attestation.
- SHA-pinned GitHub Actions references in CI and release workflows.

### Changed
- CI workflow hardened by pinning actions to immutable commit SHAs.

## [2026-03-26]

### Added
- Initial hardened test suite for strict, JSONL, meta, repair, recover, limits, timeout, wrapper tags, fixtures, and property contracts.
- Chatty-response contract tests ensuring output contains only requested JSON.
- README deployment and systemd hardening guidance.
