# Contributing to Qvacell

Thanks for your interest in improving Qvacell! This document explains how to propose changes.

## Ways to Contribute

- **Report outdated or wrong USSD codes** — the catalog is only useful if it is accurate.
- **Fix bugs** in the app.
- **Improve the UI/UX** while respecting the brand palette (navy `rgb(0,0,102)`, cyan `#09C`, black, white).
- **Improve documentation.**

## Development Setup

1. Install the toolchain: Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
2. Fork and clone the repository.
3. Generate the project: `xcodegen generate`.
4. Open `Qvacell.xcodeproj` and build.

## Updating the USSD Catalog

All codes live in `Qvacell/codes.json`. When adding or changing a code:

- Keep the JSON schema: `id`, `code`, `title`, `details`, `category`, `type`, `requiresInput`, optional `inputPlaceholder` and `mnemonic`.
- Use `{input}` inside `code` for the user-provided part.
- `type` is `ussd` for dialed sequences ending in `#`, `call` for plain numbers.
- Cite a source (ETECSA announcement, official page) in your PR description.

> [!IMPORTANT]
> `codes.json` is also consumed by the web version of the project. Modifying its schema or structure without coordination can break the web interface.

## Pull Request Process

1. Create a feature branch from `main`: `git checkout -b feat/short-description`.
2. Make focused commits following [Conventional Commits](https://www.conventionalcommits.org/):
   - `feat: add roaming status code`
   - `fix: encode # in dial url`
   - `docs: update catalog table`
3. Ensure the project builds without warnings.
4. Fill in the pull request template.
5. A maintainer will review your PR; please respond to feedback.

## Code Style

- Swift 5.9+, SwiftUI-first.
- All code, comments and identifiers in **English**.
- Prefer small, focused views and value types.
- No third-party dependencies unless discussed in an issue first.

## Questions

Open a [discussion issue](.github/ISSUE_TEMPLATE) — we're happy to help.
