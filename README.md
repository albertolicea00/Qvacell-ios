# 🇨🇺 Qvacell

> Your cell in Cuba. We changed the letter, kept the sound.

[![Platform](https://img.shields.io/badge/platform-iOS%2017.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/swift-5.9%2B-orange.svg)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-15.0%2B-blue.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)
<!-- [![WiFi rooms sync](https://github.com/albertolicea00/qvacell-ios/actions/workflows/wifi-rooms-sync-check.yml/badge.svg)](https://github.com/albertolicea00/qvacell-ios/actions/workflows/wifi-rooms-sync-check.yml) -->

An iPhone app to quickly access the **USSD service codes of ETECSA (Cubacel)** : check your balance, buy data/voice/SMS plans, transfer credit and more — all from a clean, organized list that hands the code straight to the system dialer.

[Mira la versión en español](README.es.md)

## ⚠️ Disclaimer

> [!WARNING]
> This is an independent, community-made app. It is **not affiliated with, endorsed by, or sponsored by ETECSA**.  
> Codes may change at any time at the carrier's discretion.

## ✨ Features

- 📋 **Full USSD Catalog** — Organized by categories (Balance & Plans, Purchases, Transfers, Utilities) with input-aware prompts.
- 📞 **One-Tap Dialing** — Instant execution opening the native system dialer with `#` properly encoded.
- 👤 **Contact Integration** — Access device address book to call, transfer credit, or place `*99` collect calls directly.
- 🆔 **Caller ID Extension** — CallKit extension labeling incoming `*99` collect calls with the contact's real name.
- 🛜 **Wi-Fi & Navigation Directory** — Offline search for ETECSA navigation rooms and public Wi-Fi hotspots by province.
- ✉️ **SMS Services Catalog** — Browse and prefill SMS service queries (news, weather, sports, utility rates) without silent sending.
- 📶 **Internet Speed Test** — Built-in ping, download, and upload speed test gauge powered by Cloudflare endpoints.
- 👥 **Account & PIN Management** — Store transfer PIN in Keychain and manage Plan Amigo numbers easily.
- 🔔 **Local Reminders** — Schedule recurring alerts for plan purchases, balance top-ups, or transfers with 1-tap dial action.
- 🎙️ **Siri & Voice Shortcuts** — Execute balance queries, quick codes, and collect (`*99` / 99) or anonymous (`#31#` / oculto / privado) calls via native voice commands using `AppIntents`.
- 🌗 **Customization & Settings** — Light/Dark theme support, custom accent color picker, and configurable launch tab.

### Upcoming
- **Online Phone Directory Search** — Web scraper backend integration for online phone number lookups. See [#2](https://github.com/albertolicea00/Qvacell/issues/2) for details.
- **Yellow Pages Integration** — Web scraper backend integration to search ETECSA Yellow Pages by category, number, municipality, and province. See [#3](https://github.com/albertolicea00/Qvacell/issues/3) for details.

## 🛠️ Requirements

- 🍏 Xcode 15+
- 📱 iOS 17.0+
- ⚙️ [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## 🚀 Getting Started

```bash
git clone https://github.com/albertolicea00/qvacell-ios.git
cd qvacell-ios
xcodegen generate
open Qvacell.xcodeproj
```

> **Note on XcodeGen:** This project uses **XcodeGen** with a `project.yml` specification to generate `Qvacell.xcodeproj` dynamically and prevent `.pbxproj` merge conflicts.

Build and run on a device. **USSD dialing requires a physical iPhone with a Cubacel SIM** 📲 — the simulator cannot place calls.

To get Caller ID working for `*99` collect calls, after installing the app go to **Ajustes (Settings) › Teléfono › Bloqueo e Identificación de Llamadas** on the device and enable **CallerID**. This is a one-time, manual iOS setting — no app can enable it automatically. See [ARCHITECTURE.md § 11](ARCHITECTURE.md#11-caller-id-extension-99-collect-call-identification) for why.

## 🗂️ Project Structure

```
Qvacell/
├── QvacellApp.swift  # App entry point
├── Models.swift              # USSDCode, USSDCategory, catalog decoding, brand palette, Reminder/ReminderTemplate
├── Services.swift            # JSON catalog store, Contacts, system dialer bridge, ReminderManager (local notifications)
├── UIComponents.swift        # Reusable presentational views (code row)
├── Views.swift               # Home, Contactos, category, and settings screens
├── codes.json                # Bundled USSD code catalog
└── wifi_navigation_rooms.json  # Bundled ETECSA navigation-room/hotspot directory

CallerIDExtension/             # CallKit Call Directory Extension (labels *99 collect calls)
└── CallDirectoryHandler.swift

Shared/                        # Code shared by the app and CallerIDExtension
└── CallerIDStore.swift        # App Group–backed caller-ID list (read/write)
```

*The full USSD code catalog is dynamically loaded from our JSON configuration file [`Qvacell/codes.json`](Qvacell/codes.json), keeping the app lightweight and easy to update.* 📁

## ☎️ Direct Dial vs. Confirmation

Free query codes dial immediately. Paid purchase codes stop at ETECSA's confirmation menu by default; an optional **Acción Rápida sin Confirmación** setting enables auto-confirming code variants with a visible UI safety warning.

## 🔍 Directory (Reverse Lookup)

Provides local (user-imported database) and online web search options under Ajustes › Utilidades. For privacy, search is strictly number-only (no name lookup), and results copy to clipboard rather than auto-dialing.

## 🛜 Navigation Rooms & Public Wi-Fi

Includes an offline directory of official ETECSA navigation rooms and public Wi-Fi hotspots by province ([`wifi-rooms-sync-check`](.github/workflows/wifi-rooms-sync-check.yml) action monitors source data drift).

## 🚧 Known Limitations

- **Directory database not integrated with Caller ID (`*99`).** The directory database (see above) is intentionally kept separate from `CallerIDStore`/`CallDirectoryHandler` (see [ARCHITECTURE.md § 11](ARCHITECTURE.md#11-caller-id-extension-99-collect-call-identification)), which only ever loads from the device's own Contacts. A CallKit Call Directory Extension has a hard cap on how many identification entries it can register (historically on the order of 100k–200k) — the directory dump has millions of rows (v1: ~4.6M; v2: ~4.8M combined), so registering it wholesale would get the extension rejected/disabled by iOS. Feeding it in would need a drastic filter (e.g. only numbers already in the device's own contacts, which is exactly what happens today) to fit under that ceiling.

- **No "call via WhatsApp/Teams" option in Contactos.** The Contactos tab only offers cellular actions (normal call, `*99` collect, `#31#` anonymous) next to each contact — it can't add a "call via WhatsApp" or "call via Teams" option alongside them. Those apps place calls over their own proprietary VoIP/Wi-Fi-calling stack, not the cellular network, and don't expose any public API or URL scheme a third-party app can use to trigger a call through them — that's entirely up to WhatsApp/Teams themselves (they'd need to register their own CallKit provider and/or an app-specific integration), not something Qvacell can add from the outside.

- **iOS security sandbox and USSD limitations (no real-time balance tracking).** Unlike Android (where apps can intercept USSD responses in the background), iOS sandbox security prevents third-party apps from reading or parsing USSD response dialogs, chaining sessions automatically, or running background USSD queries. Because of this system limitation, the app cannot automatically display or update your balance, data packages, or bonus balances in real-time inside the app UI; dialing a code (`tel://`) hands off execution to the native Phone app where the user sees the carrier response screen directly.

- **No Home Screen widget.** Considered and deliberately not built. A WidgetKit extension cannot call `UIApplication.shared.open`/`tel://` at all — `APPLICATION_EXTENSION_API_ONLY` makes that API unavailable in any app extension, widgets included, so a widget can never dial a code or place a `*99`/`#31#` call by itself. The only thing a widget *could* do is open the app via a deep link and let the app dial from there — but that adds a screen transition on top of what unlocking the phone and tapping the app icon already does, with no code actually reaching the dialer any faster. Not worth the extra target, App Group, and maintenance surface for zero real shortcut.

- **Physical dual-SIM (two nano-SIM) devices.** iPhone models sold in mainland China, Hong Kong, and Macao support two physical nano-SIMs, instead of the nano-SIM + eSIM combo sold everywhere else. This app has no line-selection UI and no way to force a dial through one SIM specifically — iOS gives apps no public API to pick which line places a `tel://`/USSD call; it always goes out through whichever line the device's own Phone settings mark as default. Acknowledged, not implemented.

- **No iPad / iPadOS support for USSD.** Even though Cellular iPad models exist (with physical SIM or eSIM slots), Apple completely blocks USSD code execution on iPadOS. iPadOS lacks a full Phone dialer application, which means users cannot dial USSD codes (such as `*222#`, `*133#`, or `*234#`), trigger `tel://*222%23` URLs from third-party apps, or receive USSD network responses.

- **No Apple Watch / watchOS support for USSD.** Similarly, Cellular Apple Watch models do not support USSD code execution or third-party USSD dialing via watchOS.

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

> ⚠️ **Issues, PR descriptions, and commit messages must be written in English.**
> The app UI is intentionally in Spanish — it targets Cuban users. All technical communication follows English conventions.

## 📚 Sources
The codes were saved from the following sites:
- https://galixpay.com/recargas-a-cuba/
- https://www.fonoma.com/blog/codigos-ussd-cuba
- https://www.etecsa.cu/es/taxonomy/term/1445
- https://www.etecsa.cu/en/rooms-public-spaces
- https://www.ecured.cu/Entumovil
- https://www.escambray.cu/2017/etecsa-informa-sobre-nuevos-servicios-de-telefonia-movil-para-clientes-prepago-infografia/
- https://www.entumovil.cu/#:~:text=Para%20activar%20las%20siguientes%20prestaciones%2C,portal%20el%20de%20su%20preferencia.

---

*Developed by @albertolicea00*