# Security Policy

## Supported Versions

Qvacell ships as a single, continuously updated iOS app (no parallel major-version branches). Only the latest release on the App Store / latest commit on `main` receives security fixes.

| Version | Supported |
| ------- | --------- |
| Latest `main` | ✅ |
| Older releases | ❌ |

## Project Threat Model (read before reporting)

This app has no backend server, no user accounts, and no network layer of its own:

- The USSD catalog (`Qvacell/codes.json`) is a static file bundled at build time.
- The only privileged action the app performs is handing a dial string to iOS via `UIApplication.open` on a `tel:`/USSD URL — it does not place calls itself.
- No analytics, no ads SDKs, no third-party dependencies (per [CONTRIBUTING.md](CONTRIBUTING.md): "No third-party dependencies unless discussed in an issue first").

Given that, realistic security concerns for this project are narrower than a typical networked app. In scope:

- **Malicious or malformed USSD codes** in `codes.json` that could dial premium-rate numbers, trigger unintended carrier actions, or crash the app via bad JSON/percent-encoding.
- **URL/string injection** in the `{input}` placeholder handling (e.g. a card number or phone number field breaking out of the intended dial string).
- **Build tooling issues** (`project.yml`, XcodeGen config, CI workflows in `.github/`) that could lead to unintended code execution during build/CI.

Out of scope: this app cannot leak account credentials, payment data, or server-side data — it holds none. Reports about ETECSA/Cubacel's own USSD/network security are out of scope for this repo; report those to ETECSA directly.

## Reporting a Vulnerability

**Do not open a public GitHub issue for a security report** — issues and PRs are public and could disclose an exploitable catalog/URL-injection bug before a fix ships.

Instead, use one of these private channels:

1. **Preferred:** [GitHub Security Advisories](https://github.com/albertolicea00/Qvacell-ios/security/advisories/new) for this repository — lets the maintainer triage privately and coordinate a fix/disclosure.
2. **Email:** contact the maintainer directly. *(Assumption — verify before publishing: use the address the repo maintainer wants listed here, e.g. the address tied to the `albertolicea00` GitHub account. If none is set, keep GitHub Security Advisories as the sole channel.)*

When reporting, please include:

- Steps to reproduce (device/iOS version, the specific USSD entry or input value involved).
- The affected file(s) (e.g. `Qvacell/codes.json`, `Services.swift`, a specific CI workflow).
- Potential impact (e.g. "dials a premium number without confirmation", "crashes on malformed input", "CI workflow allows arbitrary code injection via PR").

## Response Expectations

This is a single-maintainer, community-driven project — there is no SLA. As a target:

- Acknowledgment: within 7 days.
- Initial assessment (confirmed / not a vulnerability / needs more info): within 14 days.
- Fix or mitigation timeline communicated once triaged, prioritized by real-world impact (e.g. "silently dials a premium number" outranks a cosmetic parsing edge case).

## Disclosure

Coordinated disclosure preferred: please allow a fix to ship (or an explicit decision that no fix is planned) before public disclosure. Credit will be given in the release notes/advisory unless you request otherwise.
