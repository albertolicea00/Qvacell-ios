# Qvacell :: Architecture

For contribution workflow see [CONTRIBUTING.md](CONTRIBUTING.md).

This document describes the technical architecture of Qvacell, a native iOS app that lets users dial ETECSA (Cubacel) USSD service codes (`*222#` style dial strings) without needing to remember them.

It is a dependency-free SwiftUI app with no backend and no network calls. Almost everything comes from one read-only bundled JSON catalog; the two exceptions are the device's own Contacts (read live via the `Contacts` framework, never sent anywhere) and a small App Group file the CallerIDExtension target reads to label `*99` collect calls (§11) — there is still no server, no analytics, and no third-party dependency anywhere in the project.

---

## 1. High-Level Overview

```
┌─────────────────────────────────────────────────┐
│                QvacellApp                │
│    (App entry point · injects stores · theme)    │
└───────────────────────────┬───────────────────────┘
                            │
                            ▼
                        HomeView
              (TabView, 5 tabs: Líneas de Ayuda,
               Contactos, Home, Compras, Ajustes)
        ┌──────────┬──────────┬──────────┬──────────┐
        ▼          ▼          ▼          ▼          ▼
   CategoryListView (×2, helplines/purchase)   SettingsView
   (per-category code list · dials/prompts)    (NavigationStack, List)
        │                                              │
        ▼                                              ▼
   dial/alert/SMS-compose,             pushes: Servicios por SMS, Salas y
   depending on USSDCode.type          Zonas WiFi, Buscar en Directorio,
                                        Buscar en Database (desbloqueable),
                                        Gestionar Plan Amigo, Gestionar PIN,
                                        Identificador *99, Siri y Atajos, Ayuda
        │
        ▼
   DialService / MessageComposeView
   (tel:// URL, or system SMS compose sheet)


          USSDCodeStore ── decodes ──▶ USSDCatalog
                  │
                  └── loads Qvacell/codes.json (bundled, read-only)
```

There is no MVVM view-model layer and no cross-tab navigation state machine, but there is now more than one `@Observable` store injected at the app root: `USSDCodeStore` (the catalog) and `AccentColorStore` (the user's chosen accent color) are both handed down via `.environment`; `WifiRoomsStore` and `ContactsService` is created where they're used instead. State flows one way — stores (read-only or self-contained) → views. There is no unified "code detail sheet" anymore — each `USSDCode.type` (`.ussd`, `.call`, `.sms`) drives a different tap behavior directly (dial, alert-for-input-then-dial, or open the SMS compose sheet). Persisted state includes `@AppStorage` flags (`darkModePreference`, `defaultTab`, `showNetworkStatus`, `quickPurchaseNoConfirmDefault`, the accent color hex) and the transfer PIN in the Keychain (`TransferPinStore`, §12). This is a working app with real scope now, not the ≈380-line starting point described in earlier drafts of this document — see `git log` for the actual history instead of a stale line count here.

---

## 2. Source Layout

| File | Responsibility |
|---|---|
| `Qvacell/QvacellApp.swift` | `@main` entry point. Creates `USSDCodeStore` and `AccentColorStore` and injects both into `HomeView` via `.environment`. |
| `Qvacell/Models.swift` | `Codable` catalog models (`USSDCatalog`, `USSDCategory`, `USSDCodeGroup`, `USSDCode`, `USSDActionType`, `SMSVariant`), `CubanPhoneNumber` (the one place that validates a Cuban mobile number), the brand palette (`Color.brandNavy`, `.brandCyan`, `.appBackground`, `.appForeground`, hex round-tripping for the user's accent color), `AppTheme.codeFont`, and the WiFi navigation-room models (`WifiProvince`, `WifiRoom`, `WifiHotspotGroup`). |
| `Qvacell/Services.swift` | `USSDCodeStore` (loads/decodes `codes.json`), `AccentColorStore` (user's accent color, `UserDefaults`-backed), `WifiRoomsStore` (loads `wifi_navigation_rooms.json`), `ContactsService` (reads the device address book, rebuilds the CallerID list on every fetch — §11), `CellularMonitor`, `DialService` (builds/opens `tel://` URLs), `MapsService` (opens Apple/Google Maps as a place search), `TransferPinStore` (Keychain-backed transfer PIN, §12), `DirectoryDatabase` (SQLite reverse-lookup over a user-supplied dump, §13), and `ReminderManager` (local-notification scheduling, §6). |
| `Qvacell/UIComponents.swift` | Reusable, presentation-only views: `CodeRowView`, `ContactRowView`, plus `ContactPickerView` and `MessageComposeView` (thin `UIViewControllerRepresentable` wrappers around the system contact picker and SMS compose sheet). |
| `Qvacell/Views.swift` | `HomeView` (the root `TabView`), `HomeQuickActionsView` (Home tab), `CategoryListView` (Líneas de Ayuda / Compras tabs), `ContactsListView` and friends (Contactos tab), `SMSServicesView`/`SMSCodeListView`/`SMSOptionPickerView` (Servicios por SMS), `SettingsView` and everything it pushes: `WifiRoomsProvinceListView`/`WifiRoomsDetailView`, `YellowPagesSearchView` ("Buscar en Directorio"), `DirectorySearchView` ("Buscar en Database", offline, hidden by default), `FriendsPlanManageView`, `TransferPinSettingsView`, `CallerIDSettingsView`, `SiriShortcutsHelpView`, and `HelpSettingsView`. This is the largest file in the project by a wide margin — check it directly rather than trusting a stale summary here as new screens get added. |
| `Qvacell/codes.json` | Static, bundled dataset: version, carrier, categories → groups → codes, each with its dial string and presentation metadata (§3). |
| `Qvacell/wifi_navigation_rooms.json` | Static, bundled dataset: one entry per province with its navigation rooms and free WIFI hotspots (§ Navigation Rooms in the README). |
| `Qvacell.xcassets/` | `AccentColor` (brand cyan, `#09C` — the *default*; the user can override it at runtime via `AccentColorStore`, unlike the asset catalog value itself) and `AppIcon`. |
| `Shared/CallerIDStore.swift` | `CallerIDEntry` model plus read/write helpers for the App Group file both `Qvacell` and `CallerIDExtension` touch — the only file compiled into *both* targets (§11). |
| `CallerIDExtension/CallDirectoryHandler.swift` | The `CXCallDirectoryProvider` subclass — the entire CallerIDExtension target (§11). |

No separate persistence layer, networking layer, or dependency-injection container exists — `Services.swift` *is* the service layer, and there is exactly one store instance, created once and passed down.

---

## 3. Configuration Data: `codes.json`

`codes.json` is the single source of truth for **what USSD/call/SMS codes exist** and is treated as read-only, bundled data. It decodes into:

```
USSDCatalog
 ├─ version, carrier
 └─ categories: [USSDCategory]
     ├─ id, name, icon (SF Symbol)
     └─ groups: [USSDCodeGroup]        (a named sub-heading, or nil-named for no header)
         ├─ name: String?
         └─ codes: [USSDCode]
             ├─ id, code, title, details
             ├─ icon, price, compact, showsNumber   (all optional — presentation hints, see Models.swift)
             ├─ type: USSDActionType   (.ussd / .call / .sms — drives dial-vs-alert-vs-compose behavior)
             ├─ requiresInput: Bool, inputPlaceholder: String?
             ├─ noConfirmCode: String?             (Quick-Purchase-without-confirmation variant of `code`)
             ├─ smsBody: String?                   (for `.sms` codes: the message text sent to `code`)
             ├─ options: [String]?                 (for `.sms` codes with a fixed picker of message bodies)
             ├─ isSubscription: Bool?
             └─ variants: [SMSVariant]?             (label + smsBody pairs, for a small fixed choice set)
```

A code carries no `category` field of its own — its category and group are entirely implied by where it sits in the nested JSON (see the doc comment on `USSDCode` in `Models.swift`). There is no `mnemonic` field.

`USSDCodeStore.load(from:)` reads and decodes this once, synchronously, at `init`. There is **no schema versioning enforcement and no remote fetch** — updating codes requires shipping a new app build. A missing or malformed catalog trips an `assertionFailure` in debug and renders an empty list in release; since the file is bundled, this only happens on developer error.

---

## 4. Navigation Model

`HomeView` is a bottom `TabView` with 5 explicit tabs — Líneas de Ayuda, Contactos, Home, Compras, Ajustes — not a generic loop over every catalog category (the tab order is hardcoded on purpose: Home must sit in the middle). Líneas de Ayuda and Compras each host a `CategoryListView` bound to the matching `USSDCategory` (`helplines`/`purchase`) from `store.tabCategories`; adding a *code or group* to either category in `codes.json` updates that tab automatically, but adding a whole new top-level category does **not** grow the `TabView` — the tab set itself is fixed.

Each `CategoryListView` is a `NavigationStack` wrapping a `List` of that category's groups/codes. Tapping a row dials/prompts/composes directly depending on `USSDCode.type` and `requiresInput` — there is no shared "code detail" sheet type; see §5.

`SettingsView` is its own `NavigationStack` wrapping a `List` (not a `Form`), entirely separate from the category tabs. Unlike the original single-screen design, it now has real navigation depth — `NavigationLink`s push `SMSServicesView`, `WifiRoomsProvinceListView`, `YellowPagesSearchView` ("Buscar en Directorio"), `DirectorySearchView` ("Buscar en Database", when unlocked), `FriendsPlanManageView`, `TransferPinSettingsView`, `CallerIDSettingsView`, `SiriShortcutsHelpView`, and `HelpSettingsView`. "Pestaña Inicial" (`@AppStorage("defaultTab")`) can point at one of those nested screens instead of a bare tab; `SettingsView.onAppear` auto-pushes the matching one exactly once per launch via a dedicated `isShowing*OnLaunch` flag per destination (see `HomeTab.launchOptions`/`.tabToSelect`). Persisted `@AppStorage` state now includes `darkModePreference`, `defaultTab`, `showNetworkStatus`, and `quickPurchaseNoConfirmDefault`, plus the accent color hex (`AccentColorStore`) and the transfer PIN (Keychain, not `UserDefaults` — §12).

---

## 5. Code Execution Path

There is no single "code detail" sheet — what a tap does depends on `USSDCode.type`:

1. **Row tap, no input required** (`requiresInput == false`): dials/composes immediately — see step 3/4 below for what "dials" means per type.
2. **Row tap, input required** (`requiresInput == true`): an alert (in `CategoryListView`/`SettingsView`, depending on where the code lives) shows a `TextField` and disables the confirm button until it is non-empty; `USSDCode.resolvedCode(input:)` (or `resolvedSMSBody(input:)` for `.sms`) substitutes the `{input}` placeholder.
3. **`.ussd`/`.call`**: `DialService.dial(_:)` percent-encodes `#` as `%23` (iOS rejects a raw `#` in a `tel://` URL), builds the `tel://` URL, and calls `UIApplication.shared.open`. Returns `false` when the device cannot place calls (iPad, simulator, Wi-Fi-only) instead of failing silently.
4. **`.sms`**: opens `MessageComposeView` (wraps `MFMessageComposeViewController`) prefilled with `code` as the recipient and the resolved `smsBody` as the message — never sent silently, same one-more-tap-to-confirm shape as a `tel://` dial. Codes with `options` show a picker of valid message bodies first (`SMSOptionPickerView`); codes with `variants` show a small fixed choice instead.
5. **Quick Purchase, no confirmation** (opt-in, Compras only): when the "Acción Rápida sin Confirmación" toggle is on and the code has a `noConfirmCode`, that string is dialed instead of `code` — it auto-selects ETECSA's own "¿Confirma su compra? 1. Sí" step in one dial instead of stopping there. See README § Direct dial vs. confirmation.

There is no prefill/resolver indirection beyond the `{input}`/named-placeholder substitution above (unlike apps that inject saved user data before dialing) — separately, the Home Transferir card and the offline Database search (`DirectorySearchView`) *do* prefill a "Clave" field from `TransferPinStore` (§12), but that's local to those specific screens, not a general mechanism.

---

## 6. Reminders & Local Notifications

Ajustes › Utilidades › Recordatorios schedules `UNUserNotificationCenter` local notifications for a purchase/recharge/transfer the user needs to make — entirely on-device, no push infrastructure, no server, consistent with §1's "no backend, no network calls."

### 6.1 Model & manager

- `Reminder` (`Models.swift`): `title`, `message`, `iconName`, `ussdCodeId` (nilable `USSDCode.id` to resolve via `USSDCodeStore` at execute time), `phoneNumber` (destination number for a transfer reminder — unused by every other template), `date`, `recurrence` (`ReminderRecurrenceKind`: `.none`/`.daily`/`.weekly`/`.monthly`/`.custom`), `customIntervalDays`, `isEnabled`, `templateKey`.
- `ReminderTemplate` (`Models.swift`, static catalog): Comprar Paquete, Hacer Transferencia, Recargar Saldo, plus `.custom` (from-scratch). Each carries a `ReminderTemplateAction` (`.openPurchases` / `.dialSingleInput` / `.dialTransfer` / `.none`) re-resolved from `Reminder.templateKey` at execute time rather than snapshotted on the reminder itself, since a custom reminder has no direct action at all.
- `ReminderManager` (`Services.swift`, `NSObject` + `@Observable` + `UNUserNotificationCenterDelegate` singleton, injected via `.environment` like the other stores): CRUD over `reminders` (`UserDefaults`-backed), schedules/reschedules `UNNotificationRequest`s on every mutation, and handles notification taps/actions.
- `TabRouter` (`Services.swift`, `@Observable`): the one piece of cross-tab navigation state in the app (§4 otherwise has none) — lets a reminder's "Ejecutar" action switch `HomeView`'s active tab from a presented sheet without threading `selectedTab` down to every modal.

### 6.2 Multiple instances per template

`RemindersListView` renders one `Section` per `ReminderTemplate` with every matching `Reminder` (`ReminderManager.reminders(forTemplate:)`) listed underneath, plus an "Agregar `<template>`" row — so the same template can be reused any number of times (one reminder per phone line, for instance). `AddReminderView` auto-suggests a distinguishing title ("Hacer Transferencia — 51234567") from the phone number as it's typed, unless the user has already edited the title themselves (`isTitleCustomized` flag) — otherwise every instance created from the same template would default to an identical, indistinguishable title.

### 6.3 Scheduling

Same trigger mapping as every other `UNNotificationTrigger`-based scheduler: `.none`/`.daily`/`.weekly`/`.monthly` use `UNCalendarNotificationTrigger` with matching date components; `.custom` (every N days) uses `UNTimeIntervalNotificationTrigger(timeInterval: days * 86400, repeats: true)`, which fires `interval` seconds after it's *scheduled*, not at the user-picked date — there is no iOS API for "start on this date, then repeat every N days." `.monthly` also skips firing in a month lacking that day-of-month (e.g. day 31 in February). Both are inherent trigger limitations, not bugs.

### 6.4 Notification tap → detail → "Ejecutar"

`UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:)` sets `deepLinkReminder`; `HomeView`'s `.sheet(item:)` (bound to it via a `Binding(get:set:)`, since `@Observable` needs `@Bindable` only for a true two-way binding, which a plain get/set closure sidesteps) opens `ReminderDetailView` regardless of which tab is active. Two custom notification actions — `REMINDER_MARK_DONE`, `REMINDER_SNOOZE_1_DAY` — resolve a reminder straight from the notification without opening the app; the default tap opens the detail sheet instead.

`ReminderDetailView`'s "Ejecutar" button branches on the resolved template's `action`:

| Action | Template | Behavior |
|---|---|---|
| `.openPurchases` | Comprar Paquete | Sets `tabRouter.pendingTab = .purchase` and dismisses — there is no single fixed code for "buy a package" (it's a whole catalog of choices by data/duration), so this hands the user off to Compras instead of guessing. |
| `.dialSingleInput` | Recargar Saldo | Opens `ExecuteReminderSheet`, which asks for the card number (never knowable ahead of time — it's scratched off a physical card at purchase) and dials `store.code(withId: "recharge-card")!.resolvedCode(input:)`. |
| `.dialTransfer` | Hacer Transferencia | Opens `ExecuteReminderSheet` with phone number prefilled from the reminder and PIN prefilled from `TransferPinStore.load()` (§12) — both editable — asks for the amount fresh, then dials `resolvedCode(with: ["phoneNumber":, "pin":, "amount":])`, the same substitution `HomeQuickActionsView`'s own Transferir card uses (§5). |
| `.none` | Personalizado | No "Ejecutar" button at all — just a note. |

### 6.5 Known limitations

- No schema versioning on `Reminder`, same as `codes.json` itself (§9).
- Notifications only — a reminder is never synced anywhere; there is no iCloud/cross-device story for it (nor for anything else in this app, per §1).

---

## 7. Theming

- **Brand palette**: `Color.brandNavy` (`rgb(0,0,102)`) and `Color.brandCyan` (`#09C`) are fixed static properties on `Color`, defined in `Models.swift`. `brandCyan` is only the *default* accent now — `AccentColorStore` (`Services.swift`) holds the user's actual choice, made via a `ColorPicker` in Ajustes › Preferencias, persisted as a hex string in `UserDefaults` (`Color` itself isn't storable there — `Color.hexString`/`init?(hex:)` in `Models.swift` do the round-trip). Every view that used to hardcode `.brandCyan`/`Color.brandCyan` for its accent now reads `accentColorStore.color` via `@Environment(AccentColorStore.self)` instead — `AccentColor` in the asset catalog still matches the *default* cyan, but the live tint can differ from it once the user picks something else. Inline `Picker`s inside a `List` don't reliably inherit `.tint()` from an ancestor for their selected-value text/chevron, so those are tinted directly rather than relying on inheritance.
- **Adaptive colors**: `Color.appBackground`/`.appForeground` wrap `UIColor.systemBackground`/`.label` so light/dark mode "just works" by default.
- **Dark mode override**: `SettingsView` exposes a "Theme" picker (System Default / Light / Dark) backed by `@AppStorage("darkModePreference")` (`Int`, 0/1/2). `QvacellApp` reads the same key and applies `.preferredColorScheme(nil/.light/.dark)` to the root `WindowGroup` content — the one piece of state in the app that is both user-configurable and persisted across launches.
- **Typography**: `AppTheme.codeFont(size:)` is the one shared style — a semibold monospaced font — used everywhere a dial string is displayed, so codes always read as "code" rather than prose.
- All color usage in views must go through these tokens; no ad-hoc colors.

---

## 8. Platform Constraints

These shape the UX and are not fixable in code:

- iOS shows a confirmation prompt before dialing any `tel://` URL — the app cannot dial silently (by design, and good).
- Interactive multi-step USSD menus (`*133#`, `*234#`) may not render session responses the way Android does — there is no in-app fallback for that beyond dialing again.
- `*#06#` (IMEI) is parsed by the dialer only when typed manually; via `tel://` it generally does nothing.
- Simulator and Wi-Fi-only devices cannot place calls; `DialService.dial` returns `false` there.

---

## 9. Notable Constraints & Trade-offs (for future contributors)

- **No dependency injection / testability seams**: stores (`USSDCodeStore`, `AccentColorStore`, `WifiRoomsStore`) are created once and passed via `.environment` or plain `init` — there is no protocol/mock seam. Still not a real problem given the app's size, but there's now meaningfully more surface (six-plus `@Observable`/enum services) than when this was first written.
- **Silent failure on decode errors**: a malformed `codes.json` or `wifi_navigation_rooms.json` trips `assertionFailure` in debug and silently renders an empty list in release, rather than surfacing an error — acceptable only because both files are bundled and never user-supplied.
- **No data migrations**: `codes.json` has a `version` field that nothing currently reads; adding a new field to `USSDCode` is safe (optional fields decode fine), but renaming/retyping an existing field will break decoding for the exact build that ships it.
- **`codes.json`/`wifi_navigation_rooms.json` are compiled-in**: adding a new code, category, or WiFi room requires a new app build and App Store review — there is no remote-config or in-app update path, unlike apps whose `version` field exists specifically to unlock that later (see Extension Points below). Contrast this with the offline Database search (§13), which deliberately reads a file the user supplies at runtime instead.

---

## 10. Extension Points

- **New code, group, or category** → edit `codes.json` only; UI adapts automatically for a new code/group. A whole new top-level category needs a matching tab wired into `HomeView` (see §4 — the tab set is no longer a generic loop).
- **Search** → `CategoryListView`/`SMSServicesView` already filter locally as-you-type; no `USSDCodeStore` API exists for this (`code(withId:)` and `group(named:)` are point lookups, not search).
- **Favorites / recents** → `TransferPinStore` (§12) is already a precedent for small Keychain-backed state beside the read-only catalog; a `UserDefaults`-backed store would work the same way for something non-secret.
- **Remote catalog updates** → replace `USSDCodeStore.load(from:)` with a cached-remote strategy; the `version` field in the JSON exists for this.
- **Localization** — UI copy is Spanish (not English); catalog `title`/`details` would move to localized variants keyed by the same `id`.

---

## 11. Caller ID Extension (`*99` collect-call identification)

### 11.1 Why this exists

ETECSA's `*99` collect-call service does **not** withhold the caller's number the way `#31#` (anonymous) does — it wraps it. Dialing `*99{number}` makes the call arrive on the other end with a caller ID string of the form:

```
99 + "53" (country code) + {8-digit local number} + 99
```

e.g. a call to `51234567` shows up as `99535123456799` (14 digits) instead of the real number. iOS's stock Phone app has no idea what to do with that, so the incoming call just shows a meaningless 14-digit string. Since the real digits genuinely reach the device (unlike a truly anonymous call, which never transmits them — see the in-app "Ayuda" copy on this), it's possible to reverse the wrapping and show the real contact's name instead. Apple's supported mechanism for that is a **CallKit Call Directory Extension**.

### 11.2 How it works

```
Qvacell (main app)                 CallerIDExtension (app extension)
──────────────────────────                 ────────────────────────────────
ContactsService.fetch()
  reads CNContactStore
  → [DeviceContact]
        │
        ▼
CallerIDStore.wrappedNumber(...)
  "99" + "53" + localNumber + "99"
        │
        ▼
CallerIDStore.write([CallerIDEntry])  ──▶  App Group container (shared file)
  group.com.qvacell.shared          "caller-id-entries.json"
        │                                          │
        ▼                                          ▼
CXCallDirectoryManager.reloadExtension  ──▶  CallDirectoryHandler.beginRequest(with:)
  (tells iOS to re-run the extension)          CallerIDStore.read()
                                                → context.addIdentificationEntry(...)
                                                  for each entry, ascending order
                                                → context.completeRequest()
```

- **`Shared/CallerIDStore.swift`** is compiled into *both* targets. It defines `CallerIDEntry` (`wrappedNumber: Int64`, `name: String`), the wrapping formula, and JSON read/write against a file in the App Group container (`group.com.qvacell.shared`) — the only way for two separate sandboxed processes (the app and the extension) to share data.
- **`ContactsService.fetch()`** (in `Qvacell/Services.swift`) rebuilds the full entry list from `contacts` every time it re-fetches from `CNContactStore`, writes it via `CallerIDStore.write(_:)`, then calls `CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier:)` so iOS re-invokes the extension immediately rather than waiting for its own schedule. This keeps the Caller ID list in sync automatically — there is no separate manual "sync" button in the UI.
- **`CallerIDExtension/CallDirectoryHandler.swift`** is the entire extension target: a `CXCallDirectoryProvider` subclass that reads the shared file and calls `addIdentificationEntry(withNextSequentialPhoneNumber:label:)` once per contact, in strictly ascending numeric order (a hard CallKit requirement — the request is rejected otherwise), then `completeRequest()`. It never touches `CNContactStore` itself and has no Contacts permission of its own — everything it shows was computed by the main app.

### 11.3 Real constraints (not fixable in code)

- **Only labels contacts already in the address book.** A `*99` call from an unknown number still shows the raw wrapped digits — same limitation as Truecaller-style apps for unrecognized numbers.
- **The user must enable it once, manually**: Ajustes del sistema › Teléfono › Bloqueo e Identificación de Llamadas › CallerID. No API lets an app turn this on for itself.
- **Requires the App Groups capability to be signed correctly** (`group.com.qvacell.shared`, declared in both targets' entitlements in `project.yml`). With automatic signing this is normally provisioned by Xcode the first time you build with a real Team ID; if identification silently doesn't show up, check that the App Group actually got created under that team in the Apple Developer portal.
- **Only testable on a physical iPhone.** The simulator has no real telephony stack, so this cannot be verified with `xcrun simctl` screenshots the way the rest of the UI in this repo is — it needs an actual incoming `*99` call on a device with the extension enabled.
- **A truly anonymous call (`#31#`) can never be identified this way** — see §8 platform constraints; the network never transmits the number at all in that case, so there is nothing for `CallerIDStore` to wrap or unwrap.

---

## 12. Transfer PIN Store

`TransferPinStore` (`Services.swift`) persists the user's ETECSA transfer PIN in the device Keychain (`kSecClassGenericPassword`), not `UserDefaults` — it's the one piece of user-entered state in the app sensitive enough to warrant that. `.save(_:)`/`.load()`/`.delete()` wrap `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete` directly (no third-party Keychain wrapper). The stored item's accessibility is `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — it never syncs via iCloud Keychain and is excluded from device backups, so reinstalling the app or restoring from backup loses it (by design: it's read back into a plaintext `TextField`, unlike a password, so it shouldn't survive a device transfer silently).

Consumers: the Home Transferir card and the offline Database search's "Clave" field both call `TransferPinStore.load()` to prefill themselves instead of asking the user to retype the PIN every time; `TransferPinSettingsView` (Ajustes › Cuenta › Gestionar PIN de Transferencia) is the only place that writes to it.

---

## 13. Offline Database Search / DirectoryDatabase (`Buscar en Database`)

`DirectoryDatabase` (`Services.swift`) is a raw SQLite reader (`import SQLite3`, no wrapper library) powering the "Buscar en Database" screen (`DirectorySearchView`) over a phone-directory dump the *user* supplies — the app neither bundles nor downloads it. (Note: in the UI, "Buscar en Directorio" refers to the online directory search (`YellowPagesSearchView`), while this offline SQLite search is named "Buscar en Database" and unlocked via the 5-tap version easter egg). It looks for any `.db` file in the app's Documents directory (reachable via Finder's "On My iPhone" file sharing, enabled via `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace` in `project.yml`) and identifies its schema by querying `sqlite_master` for table names rather than trusting the filename:

- **v1**: a single `contacts(number, name, is_mobile)` table.
- **v2**: split into `movil(number, name)` and `fix(number, name)` tables — no `is_mobile` column, since which table a row came from *is* the line type.

Two non-obvious implementation details worth knowing before touching this code:

- **Opens via `file:...?immutable=1` URI, not a plain path.** Plain `SQLITE_OPEN_READONLY` still makes SQLite take a shared lock and probe for a hot journal on first real access; inside the iOS sandbox that first access can fail with `SQLITE_CANTOPEN` ("unable to open database file") even though the exact same file opens and reads fine at the raw POSIX level. `immutable=1` tells SQLite the file will never change while open, skipping locking and the journal probe entirely — this was found and fixed after reproducing the failure with a raw `FileHandle` read succeeding where `sqlite3_prepare_v2` didn't.
- **Only `number` is index-backed** (`v1.contacts`'s primary key, `v2.movil`'s primary key, an explicit index on `v2.fix.number`); `name` has an index too, but `LIKE '%x%'` can't use any B-tree index regardless — a name-only search is a genuine full-table scan over dumps with millions of rows. `DirectoryDatabase.minimumNumberQueryLength`/`.minimumNameQueryLength` (3 and 5) exist to bound how bad that gets, and callers must run `search` off the main thread.
- Name search is currently **disabled in the UI** for privacy/security reasons (see README § Phone Directory & Offline Database Search) even though `DirectoryDatabase.search` itself still supports a `nameQuery`.

---

## 14. Cross-Platform Catalog Sync Check

`Qvacell/codes.json` and `Qvacell/wifi_navigation_rooms.json` are maintained as two separate files — one per platform repo — rather than a shared package, so nothing enforces at build time that this repo's copy still matches [qvacell-apk](https://github.com/albertolicea00/Qvacell-apk)'s (the Android app). [`.github/workflows/cross-platform-sync-check.yml`](.github/workflows/cross-platform-sync-check.yml) is a CI guard against that drift.

### 14.1 Trigger and flow

Runs on every push to `main` touching either JSON file (plus `workflow_dispatch` for a manual run). Two independent jobs, `check-codes` and `check-wifi-rooms`, each:

1. Fetch the counterpart file from the Android repo's raw GitHub URL (`raw.githubusercontent.com/albertolicea00/Qvacell-apk/main/app/src/main/assets/...`) — no auth needed, since both repos are public.
2. Run a comparison script (`.github/scripts/check-catalog-sync.mjs` or `check-wifi-catalog-sync.mjs`) against the local copy.
3. On drift: upload the diff as a build artifact, open (or update, if one is already open) an issue **on the Android repo** — not this one — labeled `catalog-sync`, and fail the job so it shows red in Actions.
4. On no drift: exit clean.

Opening the issue on the *other* repo (rather than this one) requires the `CROSS_REPO_TOKEN` secret — a PAT with `Issues: write` on `Qvacell-apk`. Without that secret configured, the job still detects and reports drift (failed run + artifact), it just can't open the cross-repo issue.

### 14.2 What "structure" means for `codes.json`

Only these fields are compared, per code: `id`, `code` (the dial string), `type`, `requiresInput`, `inputPlaceholder`, `noConfirmCode`, `smsBody`, `options`, `isSubscription`, `variants`, plus which category id and group name it lives under (and the overall category order). Deliberately **ignored**: `icon` (SF Symbol names vs. Material icon names are expected to differ), `price`, `compact`, `showsNumber`, `title`, `details` — all presentation/wording, not behavior. This means editing a title's phrasing or swapping an icon never trips the check; changing a dial string, adding/removing a code, or moving one to a different category does.

### 14.3 What's compared for `wifi_navigation_rooms.json`

This file has no cosmetic fields — every field is data (province name, room name/address/positions, hotspot municipality/spots) — so the check compares it in full, per province, rather than filtering a subset.

### 14.4 Relationship to `wifi-rooms-sync-check.yml`

That's a separate, unrelated workflow in this same repo that checks the bundled WiFi directory against ETECSA's *own* website for source-data drift (§ Navigation Rooms in the README). This cross-platform check answers a different question — "do the two apps still agree with each other" — not "is the data still accurate against ETECSA."
