import AppIntents
import CallKit
import Contacts
import CoreTelephony
import Foundation
import Security
import SQLite3
import SwiftUI
import UIKit
import UserNotifications

let AppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
let AppBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

// MARK: - Accent Color Store

/// The user's chosen accent color (Ajustes › Preferencias), used everywhere the app used to
/// hardcode `Color.brandCyan`. Persisted as a hex string in `UserDefaults` (`Color` itself isn't
/// storable there) and defaults to `brandCyan` until the user picks something else.
@Observable
final class AccentColorStore {
    private static let key = "accentColorHex"

    var color: Color {
        didSet {
            UserDefaults.standard.set(color.hexString, forKey: Self.key)
        }
    }

    init() {
        if let hex = UserDefaults.standard.string(forKey: Self.key), let saved = Color(hex: hex) {
            color = saved
        } else {
            color = .brandCyan
        }
    }

    /// Reverts to the app's default accent (`brandCyan`) — offered in Ajustes next to the picker.
    func resetToDefault() {
        color = .brandCyan
    }
}

// MARK: - Wifi Rooms Store

/// Loads the bundled `wifi_navigation_rooms.json` (ETECSA's public navigation-room/hotspot
/// directory, one entry per province) once at init — same "load once, read-only" shape as
/// `USSDCodeStore`.
@Observable
final class WifiRoomsStore {
    private(set) var provinces: [WifiProvince] = []

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "wifi_navigation_rooms", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([WifiProvince].self, from: data)
        else {
            assertionFailure("Failed to load wifi_navigation_rooms.json from the app bundle")
            return
        }
        provinces = decoded
    }
}

// MARK: - Catalog Store

/// Loads and exposes the bundled USSD code catalog. Categories carry their own groups and
/// codes (see `USSDCategory`/`USSDCodeGroup`), so no separate flat lookup is needed here.
@Observable
final class USSDCodeStore {
    private(set) var categories: [USSDCategory] = []
    private(set) var carrier: String = ""

    /// Categories shown as their own tab — everything except the `home` category, which the
    /// Home screen renders itself (a custom layout, not a plain code list).
    var tabCategories: [USSDCategory] {
        categories.filter { $0.id != "home" }
    }

    init(bundle: Bundle = .main) {
        load(from: bundle)
    }

    /// Looks up one code by id anywhere in the catalog, regardless of which category/group holds it.
    /// Used by the Home screen to pull specific codes (main balance, transfer, recharge) into its
    /// own custom layout instead of a generic list.
    func code(withId id: String) -> USSDCode? {
        for category in categories {
            for group in category.groups {
                if let match = group.codes.first(where: { $0.id == id }) {
                    return match
                }
            }
        }
        return nil
    }

    /// Looks up a named group anywhere in the catalog — e.g. Home's "Servicio Adelanta Saldo" —
    /// so a custom layout can pull its title and codes (price, title, ...) from the catalog
    /// instead of hardcoding them in the view.
    func group(named name: String) -> USSDCodeGroup? {
        for category in categories {
            if let match = category.groups.first(where: { $0.name?.es == name }) {
                return match
            }
        }
        return nil
    }

    private func load(from bundle: Bundle) {
        guard let url = bundle.url(forResource: "codes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(USSDCatalog.self, from: data)
        else {
            assertionFailure("Failed to load codes.json from the app bundle")
            return
        }
        categories = catalog.categories
        carrier = catalog.carrier
    }
}

// MARK: - Cellular Signal Monitor

/// Tracks the device's current radio access technology so the UI can warn before a USSD
/// code is dialed with no/weak signal — USSD needs voice-network reachability, not data or Wi-Fi.
@Observable
final class CellularMonitor {
    static let shared = CellularMonitor()

    private let telephonyInfo = CTTelephonyNetworkInfo()

    private(set) var hasService = false
    /// User-facing network type label, e.g. "4G / LTE". Spanish since it is shown in the UI.
    private(set) var networkType = "Buscando red..."
    /// 0 (no service) through 3 (best).
    private(set) var signalQuality = 0

    private init() {
        updateStatus()
        NotificationCenter.default.addObserver(
            forName: .CTServiceRadioAccessTechnologyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatus()
        }
    }

    private func updateStatus() {
        guard let techByService = telephonyInfo.serviceCurrentRadioAccessTechnology,
              let tech = techByService.values.first, !tech.isEmpty
        else {
            hasService = false
            networkType = "Sin servicio celular"
            signalQuality = 0
            return
        }

        hasService = true
        switch tech {
        case CTRadioAccessTechnologyNR, CTRadioAccessTechnologyNRNSA:
            networkType = "5G"
            signalQuality = 3
        case CTRadioAccessTechnologyLTE:
            networkType = "4G / LTE"
            signalQuality = 3
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyCDMA1x, CTRadioAccessTechnologyCDMAEVDORev0,
             CTRadioAccessTechnologyCDMAEVDORevA, CTRadioAccessTechnologyCDMAEVDORevB,
             CTRadioAccessTechnologyeHRPD:
            networkType = "3G"
            signalQuality = 2
        case CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyGPRS:
            networkType = "2G / EDGE"
            signalQuality = 1
        default:
            networkType = "Red celular"
            signalQuality = 2
        }
    }
}

/// Bridges `URLSessionTaskDelegate`/`URLSessionDownloadDelegate`'s progress callbacks (which
/// aren't part of the async/await `data(for:)`/`upload(for:from:)` APIs) into a plain closure —
/// used by `DirectorySearchView`'s database download. Reports both the running total and the
/// expected total so the progress bar can show a determinate percentage.
final class TransferProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    private let onProgress: (Int64, Int64) -> Void

    init(onProgress: @escaping (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        onProgress(totalBytesSent, totalBytesExpectedToSend)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    /// Required by `URLSessionDownloadDelegate`; the async `download(for:delegate:)` API hands
    /// back the temp file URL itself, so there's nothing to do here.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

// MARK: - Device Contacts

/// One Cuban number on a contact, with iOS's own label for it ("móvil", "trabajo", "iPhone"...).
struct ContactPhoneNumber: Hashable {
    let label: String
    let number: String
}

/// One entry from the device address book: just enough to list and dial it. Contacts can carry
/// several Cuban numbers (e.g. two SIMs, a landline plus a mobile) — `numbers` keeps all of
/// them, distinctly labeled, since limiting to one caused identification/dialing to silently
/// pick the wrong line for contacts with more than one Cuban number.
struct DeviceContact: Identifiable, Hashable {
    let id: String
    let name: String
    let numbers: [ContactPhoneNumber]

    /// Primary number shown by default — first one found on the contact.
    var phoneNumber: String { numbers[0].number }
}

/// Loads one contact's thumbnail at a time, on demand — the bulk fetch used to pull
/// `CNContactThumbnailImageDataKey` for every contact up front, which held every photo's `Data`
/// in memory for the whole session and could OOM-kill the app on address books with many
/// photos. Results are cached so scrolling back to a row doesn't re-fetch it.
enum ContactThumbnailLoader {
    private static let store = CNContactStore()
    private static let cache = NSCache<NSString, UIImage>()

    /// Runs the (synchronous, XPC-backed) Contacts lookup on a plain background queue rather
    /// than inline in the caller's `async` context — doing it inline would block a thread in
    /// Swift's cooperative pool and trip the "unsafeForcedSync" diagnostic.
    static func thumbnail(forContactID id: String) async -> UIImage? {
        if let cached = cache.object(forKey: id as NSString) {
            return cached
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = (try? store.unifiedContact(
                    withIdentifier: id,
                    keysToFetch: [CNContactThumbnailImageDataKey as CNKeyDescriptor]
                )).flatMap { $0.thumbnailImageData }.flatMap { UIImage(data: $0) }
                if let image {
                    cache.setObject(image, forKey: id as NSString)
                }
                continuation.resume(returning: image)
            }
        }
    }
}

/// Reads the full address book so the Contactos tab can render its own alphabetical list
/// instead of the one-at-a-time system picker used in Transferir. This needs full Contacts
/// access (`NSContactsUsageDescription`), unlike `ContactPickerView`, which needs no permission
/// at all since it runs out-of-process.
@Observable
final class ContactsService {
    private(set) var contacts: [DeviceContact] = []
    private(set) var isDenied = false
    /// True once the initial fetch has completed (with or without results) — lets the view tell
    /// "still loading" apart from "loaded, but no Cuban numbers found", which would otherwise
    /// both look like an empty `contacts` array and spin the loading indicator forever.
    private(set) var isLoaded = false

    private let store = CNContactStore()
    private var hasLoaded = false

    /// Requests access (once) and loads contacts. Safe to call from `onAppear` repeatedly.
    func loadIfNeeded() {
        guard !hasLoaded else { return }

        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            hasLoaded = true
            isDenied = false
            fetch()
        case .notDetermined:
            hasLoaded = true
            store.requestAccess(for: .contacts) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    if granted {
                        self?.isDenied = false
                        self?.fetch()
                    } else {
                        self?.isDenied = true
                        self?.isLoaded = true
                    }
                }
            }
        default:
            hasLoaded = true
            isDenied = true
            isLoaded = true
        }
    }

    /// Re-evaluates authorization status and re-fetches if permitted, or updates `isDenied`.
    func reload() {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            isDenied = false
            hasLoaded = true
            fetch()
        case .notDetermined:
            hasLoaded = false
            isDenied = false
            loadIfNeeded()
        default:
            isDenied = true
            hasLoaded = true
            contacts = []
            isLoaded = true
        }
    }

    /// Triggers the system permission prompt if not determined yet, or opens system Settings if denied.
    func requestAccess() {
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            hasLoaded = false
            loadIfNeeded()
        } else {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    private func fetch() {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName

        DispatchQueue.global(qos: .userInitiated).async { [store] in
            var results: [DeviceContact] = []
            try? store.enumerateContacts(with: request) { contact, _ in
                // Keep every Cuban number on the contact, not just the first — contacts with
                // several lines (two SIMs, mobile + home) need all of them for identification
                // and dialing to actually work, deduped in case the same number is repeated
                // under different labels.
                var seenNumbers = Set<String>()
                let cubanNumbers: [ContactPhoneNumber] = contact.phoneNumbers.compactMap { labeled in
                    guard let normalized = CubanPhoneNumber.normalize(labeled.value.stringValue),
                          seenNumbers.insert(normalized).inserted
                    else { return nil }
                    let label = labeled.label.map {
                        CNLabeledValue<NSString>.localizedString(forLabel: $0)
                    } ?? "otro"
                    return ContactPhoneNumber(label: label, number: normalized)
                }
                guard !cubanNumbers.isEmpty else { return }
                let name = CNContactFormatter.string(from: contact, style: .fullName) ?? "Sin nombre"
                results.append(DeviceContact(
                    id: contact.identifier,
                    name: name,
                    numbers: cubanNumbers
                ))
            }
            let sorted = results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            Self.syncCallerIDExtension(with: sorted)
            DispatchQueue.main.async { [weak self] in
                self?.contacts = sorted
                self?.isLoaded = true
            }
        }
    }

    /// Rebuilds the `*99` collect-call caller-ID list (see `CallerIDStore`) from the freshly
    /// fetched contacts and asks CallKit to reload `CallerIDExtension` with it. No-op if the
    /// user has never enabled the extension in Ajustes del sistema — `reloadExtension` still
    /// completes, CallKit just has nothing enabled to feed.
    private static func syncCallerIDExtension(with contacts: [DeviceContact]) {
        // Register every Cuban number on each contact, not just the primary one — a contact
        // with several lines should be identified no matter which one calls in. CallKit still
        // requires every wrapped number in the batch to be unique, so dedupe across the whole
        // batch (a single duplicate fails the whole extension reload).
        var seenNumbers = Set<Int64>()
        let entries = contacts.flatMap { contact in
            contact.numbers.compactMap { number -> CallerIDEntry? in
                guard let wrapped = CallerIDStore.wrappedNumber(forLocalNumber: number.number),
                      seenNumbers.insert(wrapped).inserted else { return nil }
                return CallerIDEntry(wrappedNumber: wrapped, name: contact.name)
            }
        }
        CallerIDStore.write(entries)
        CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: CallerIDStore.extensionBundleID) { _ in }
    }
}

// MARK: - Dial Service

/// Opens the system dialer with a USSD sequence or phone number.
enum DialService {
    /// Builds a `tel://` URL for the given code.
    /// `#` must be percent-encoded or the URL is rejected by iOS.
    static func dialURL(for rawCode: String) -> URL? {
        let encoded = rawCode
            .replacingOccurrences(of: "#", with: "%23")
            .replacingOccurrences(of: " ", with: "")
        return URL(string: "tel://\(encoded)")
    }

    /// Hands the code to the system dialer. Returns false when the device
    /// cannot place calls (e.g. iPad, simulator).
    @discardableResult
    static func dial(_ rawCode: String) -> Bool {
        guard let url = dialURL(for: rawCode), UIApplication.shared.canOpenURL(url) else {
            return false
        }
        UIApplication.shared.open(url)
        return true
    }

    /// Async-context variant for App Intents. Uses the completion-handler `open` API instead of
    /// `canOpenURL`/`open(_:)` — those are synchronous, XPC-backed calls that trip Swift's
    /// "unsafeForcedSync called from Swift Concurrent context" diagnostic when called from an
    /// `async` function running on the cooperative thread pool.
    @MainActor
    static func dial(_ rawCode: String) async -> Bool {
        guard let url = dialURL(for: rawCode) else { return false }
        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }
}

// MARK: - Maps Service

/// Opens the system Maps app as a place *search*, not a pin at known coordinates — ETECSA's
/// navigation-room/hotspot data only gives names and (sometimes) street addresses, never lat/lng,
/// so a search query is the only thing that makes sense here.
enum MapsService {
    /// Hands a free-text query to Apple Maps. Falls back to a Google Maps search URL if Maps
    /// itself can't be opened (e.g. no Maps app), since that URL works in any browser too.
    static func openSearch(for query: String) {
        var appleComponents = URLComponents(string: "https://maps.apple.com/")!
        appleComponents.queryItems = [URLQueryItem(name: "q", value: query)]
        if let appleURL = appleComponents.url, UIApplication.shared.canOpenURL(appleURL) {
            UIApplication.shared.open(appleURL)
            return
        }

        var googleComponents = URLComponents(string: "https://www.google.com/maps/search/")!
        googleComponents.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: query)]
        guard let googleURL = googleComponents.url else { return }
        UIApplication.shared.open(googleURL)
    }
}

// MARK: - Transfer PIN Store

/// Persists the user's transfer PIN in the device Keychain — encrypted at rest by iOS,
/// `.whenUnlockedThisDeviceOnly` so it never leaves this device (no iCloud sync, no backup) —
/// so the "Clave" field in Transferir (Home and inside a contact) can prefill itself instead of
/// asking the user to retype it every time.
enum TransferPinStore {
    private static let service = "com.qvacell.transferpin"
    private static let account = "transferPin"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Replaces (or clears, for an empty string) the stored PIN.
    static func save(_ pin: String) {
        SecItemDelete(query as CFDictionary)
        guard !pin.isEmpty, let data = pin.data(using: .utf8) else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> String? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Directory Database

/// The two schema shapes the on-device Truecaller-style dump can come in — detected from the
/// file's own tables (see `DirectoryDatabase.discoverDatabase`), never from its filename or a
/// user choice: whoever copies the file in via Finder names it whatever they want, and may not
/// know themselves which shape it is.
enum DirectoryDatabaseVersion {
    case v1
    case v2
}

/// A `.db` file found in the app's Documents folder with its schema already identified.
struct DirectoryDatabaseFile {
    let url: URL
    let version: DirectoryDatabaseVersion
}

/// One directory match: a number and the name it resolves to (blank for a few `fix` rows that
/// carry no name in the source dump).
struct DirectoryEntry: Identifiable, Hashable {
    var id: String { number }
    let number: String
    let name: String
    /// v1's own `is_mobile` column, or which of v2's two tables (`movil`/`fix`) the row came
    /// from — either way, whether this is a cell number or a landline.
    let isMobile: Bool

    /// Title-cased for display — the source dump stores names in raw caps (e.g. "ALBERTO
    /// LICEA") — never mutates `name` itself, just how a view should show it. A few names carry
    /// a literal U+FFFD (�) baked into the dump itself — some upstream encoding conversion lost
    /// that character (usually Ñ or an accented letter) before this file was ever created, so
    /// there's no original byte left to recover; shown as `*` instead of the replacement glyph.
    var displayName: String {
        guard !name.isEmpty else { return "Sin Nombre" }
        return Self.titleCased(name.replacingOccurrences(of: "\u{FFFD}", with: "*"))
    }

    /// Splits only on spaces (not on `*` or other punctuation) so a name like "CASTA*AL" stays
    /// one word — `String.capitalized` would treat `*` as a word boundary and wrongly capitalize
    /// what comes after it too.
    private static func titleCased(_ string: String) -> String {
        string
            .split(separator: " ")
            .map { word -> String in
                guard let first = word.first else { return String(word) }
                return String(first).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}

/// Reverse number/name lookup over a Truecaller-style dump the user drops into this app's
/// Documents folder — via Finder file sharing (`UIFileSharingEnabled`), the in-app file picker, or
/// the in-app download (`downloadURL`, wherever that's currently hosted). The app never bundles
/// it, and doesn't assume a filename or ask which schema it is. v1 is a single
/// `contacts(number, name, is_mobile)` table; v2 splits landline and mobile into separate
/// `fix(number, name)` / `movil(number, name)` tables — `discoverDatabase` tells them apart by
/// querying `sqlite_master` for the table names each shape actually has. Both dumps are 400+MB
/// with millions of rows and only `name` is indexed, so a name search is a full table scan:
/// callers must run `search` off the main thread and keep queries short (it refuses under 3
/// characters) to bound how bad that scan gets.
enum DirectoryDatabase {
    /// Direct-file-download URL for the current dump, wherever it's currently hosted.
    /// Whatever host this points at, it has to serve the raw bytes directly — not an HTML
    /// landing page, and not a source/archive wrapper. The downloader in
    /// `DirectorySearchView.downloadDatabase` names the saved file after this URL's
    /// last path component, so it must end in the real filename (e.g. `sqlite.db`),
    /// not just an item/tag identifier.
    
    static let downloadURL = URL(string: "https://archive.org/download/masvnbvdc/sqlite.db")!

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Opens `url` via the `file:...?immutable=1` URI form instead of a plain path. Plain
    /// `SQLITE_OPEN_READONLY` still has SQLite take a shared lock and probe for a hot journal on
    /// first real access — inside the iOS sandbox that first access can fail with
    /// `SQLITE_CANTOPEN` ("unable to open database file") even though the file itself opens and
    /// reads fine at the raw POSIX level (confirmed: a plain `FileHandle` read of the same file
    /// succeeds where `sqlite3_prepare_v2` didn't). `immutable=1` tells SQLite the file will never
    /// change while open, so it skips locking and the journal probe entirely — the standard fix
    /// for a bundled/copied read-only database on iOS.
    private static func open(_ url: URL) -> OpaquePointer? {
        var components = URLComponents()
        components.scheme = "file"
        components.path = url.path
        components.queryItems = [URLQueryItem(name: "immutable", value: "1")]
        guard let uri = components.url?.absoluteString else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            return nil
        }
        return db
    }

    /// Scans Documents for any `.db` file and opens each just long enough to read its table
    /// names, returning the first one that matches a known shape (sorted by filename, for
    /// determinism when more than one is present). `nil` if Documents has no recognizable file.
    static func discoverDatabase() -> DirectoryDatabaseFile? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let candidates = try? FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil)
        else { return nil }

        let dbFiles = candidates
            .filter { $0.pathExtension.lowercased() == "db" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in dbFiles {
            if let version = detectVersion(at: url) {
                return DirectoryDatabaseFile(url: url, version: version)
            }
        }
        return nil
    }

    /// Opens `url` read-only and checks `sqlite_master` for the table names that identify each
    /// schema shape. `nil` if it's neither (not a directory dump, or an unrelated `.db` file).
    private static func detectVersion(at url: URL) -> DirectoryDatabaseVersion? {
        guard let db = open(url) else { return nil }
        defer { sqlite3_close(db) }

        let tables = tableNames(db: db)
        if tables.contains("contacts") { return .v1 }
        if tables.contains("movil") || tables.contains("fix") { return .v2 }
        return nil
    }

    private static func tableNames(db: OpaquePointer) -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type = 'table';", -1, &statement, nil) == SQLITE_OK,
              let statement
        else { return [] }
        defer { sqlite3_finalize(statement) }

        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                names.insert(String(cString: cString))
            }
        }
        return names
    }

    /// Diagnostic twin of `detectVersion` that returns *why* a file wasn't recognized instead of
    /// just `nil` — the real `sqlite3_open`/`sqlite3_prepare` error, or the actual table names
    /// found, so a report of "wrong format" on a file that opens fine on a Mac can be traced
    /// instead of guessed at. Not on the normal discovery path (that one only needs yes/no).
    static func diagnose(at url: URL) -> String {
        var lines: [String] = []

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes?[.size] as? Int
        let posixPermissions = attributes?[.posixPermissions] as? Int
        let protectionType = attributes?[.protectionKey] as? FileProtectionType
        lines.append("exists=\(FileManager.default.fileExists(atPath: url.path)) size=\(size.map(String.init) ?? "?") posix=\(posixPermissions.map { String($0, radix: 8) } ?? "?") protection=\(protectionType.map(String.init(describing:)) ?? "?")")
        lines.append("isReadableFile=\(FileManager.default.isReadableFile(atPath: url.path))")

        // Bypass SQLite entirely: read the first 16 bytes at the raw Foundation/POSIX level to
        // tell "SQLite specifically can't open this" apart from "nothing can read this file
        // right now" (e.g. Data Protection locked, or the file provider never materialized it).
        if let handle = FileHandle(forReadingAtPath: url.path) {
            let header = handle.readData(ofLength: 16)
            try? handle.close()
            let headerString = String(data: header, encoding: .ascii) ?? "?"
            lines.append("raw header read OK, \(header.count) bytes: \"\(headerString)\"")
        } else {
            lines.append("raw FileHandle open FAILED (OS-level read denied, not an SQLite-specific issue)")
        }

        guard let db = open(url) else {
            lines.append("sqlite3_open (immutable URI) failed")
            return lines.joined(separator: "\n")
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type = 'table';", -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            lines.append("sqlite3_prepare failed (code \(prepareResult)): \(String(cString: sqlite3_errmsg(db)))")
            return lines.joined(separator: "\n")
        }
        defer { sqlite3_finalize(statement) }

        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                names.append(String(cString: cString))
            }
        }
        lines.append(
            names.isEmpty
                ? "opened fine but sqlite_master has no tables"
                : "opened fine, tables found: \(names.joined(separator: ", ")) — none match the expected v1/v2 shape"
        )
        return lines.joined(separator: "\n")
    }

    /// Minimum digits before a number search runs — a product-level floor (not a perf one, the
    /// index makes even a 1-digit prefix cheap), just to avoid a "results" list for a near-empty
    /// query.
    static let minimumNumberQueryLength = 3
    /// Minimum characters before a name search runs — this one IS a perf floor: `name` isn't
    /// indexed, so a name search is a genuine full-table scan and a shorter query is an
    /// unbounded scan for almost no signal.
    static let minimumNameQueryLength = 5

    /// Separate number/name inputs instead of one combined field: a number search is a prefix
    /// match that rides `number`'s index (cheap at any length — `LIMIT` stops the index range
    /// scan early), while a name search is `LIKE '%x%'`, which can't use any index and is a
    /// genuine full-table scan. Filling both ANDs them — SQLite narrows via the number index
    /// first and only checks `name` against that already-small result set, so it stays cheap.
    /// Synchronous and potentially slow (see type-level note) — call from a background task.
    static func search(numberQuery: String, nameQuery: String, in file: DirectoryDatabaseFile, limit: Int32 = 100) -> [DirectoryEntry] {
        let number = numberQuery.trimmingCharacters(in: .whitespaces)
        let name = nameQuery.trimmingCharacters(in: .whitespaces)
        guard number.count >= minimumNumberQueryLength || name.count >= minimumNameQueryLength else { return [] }

        guard let db = open(file.url) else { return [] }
        defer { sqlite3_close(db) }

        var clauses: [String] = []
        var patterns: [String] = []
        if !number.isEmpty {
            clauses.append("number LIKE ?")
            patterns.append("\(number)%")
        }
        if !name.isEmpty {
            clauses.append("name LIKE ?")
            patterns.append("%\(name)%")
        }
        let whereClause = clauses.joined(separator: " AND ")

        switch file.version {
        case .v1:
            // `contacts` carries its own `is_mobile` column — read it per row instead of
            // assuming one line type for the whole table.
            return rows(db: db, table: "contacts", whereClause: whereClause, patterns: patterns, limit: limit, knownIsMobile: nil)
        case .v2:
            let mobile = rows(db: db, table: "movil", whereClause: whereClause, patterns: patterns, limit: limit, knownIsMobile: true)
            guard mobile.count < limit else { return mobile }
            let landline = rows(
                db: db,
                table: "fix",
                whereClause: whereClause,
                patterns: patterns,
                limit: limit - Int32(mobile.count),
                knownIsMobile: false
            )
            return mobile + landline
        }
    }

    /// `knownIsMobile` is `nil` for v1's `contacts` (read its own `is_mobile` column per row) or
    /// a fixed value for v2's `movil`/`fix` (neither table has that column — which one it is IS
    /// the line type).
    private static func rows(
        db: OpaquePointer,
        table: String,
        whereClause: String,
        patterns: [String],
        limit: Int32,
        knownIsMobile: Bool?
    ) -> [DirectoryEntry] {
        let columns = knownIsMobile == nil ? "number, name, is_mobile" : "number, name"
        let sql = "SELECT \(columns) FROM \(table) WHERE \(whereClause) LIMIT ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        for (index, pattern) in patterns.enumerated() {
            sqlite3_bind_text(statement, Int32(index) + 1, pattern, -1, transientDestructor)
        }
        sqlite3_bind_int(statement, Int32(patterns.count) + 1, limit)

        var results: [DirectoryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let numberCString = sqlite3_column_text(statement, 0) else { continue }
            let name = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let isMobile = knownIsMobile ?? (sqlite3_column_int(statement, 2) != 0)
            results.append(DirectoryEntry(number: String(cString: numberCString), name: name, isMobile: isMobile))
        }
        return results
    }
}

// MARK: - Tab Router

/// Lets a modal (e.g. a reminder's "Ejecutar" action) switch `HomeView`'s active tab without
/// `HomeView` handing its `selectedTab` state down to every presented sheet. `HomeView` observes
/// `pendingTab` and clears it once applied.
@Observable
final class TabRouter {
    var pendingTab: HomeTab?
}

// MARK: - Reminders

/// Local notifications only — no server, no push, consistent with the app's offline-first
/// design. Persists to UserDefaults and mirrors every stored `Reminder` to a scheduled
/// `UNNotificationRequest` (or a repeating one for daily/weekly/monthly/custom).
@Observable
final class ReminderManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderManager()

    static let categoryId = "REMINDER_CATEGORY"
    static let markDoneAction = "REMINDER_MARK_DONE"
    static let snoozeAction = "REMINDER_SNOOZE_1_DAY"

    var reminders: [Reminder] = [] { didSet { save(); rescheduleAll() } }
    /// Set by the notification-tap handler; `HomeView` presents this as a sheet so the user lands
    /// on the reminder's own detail instead of a bare banner.
    var deepLinkReminder: Reminder?

    private override init() {
        super.init()
        load()
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryId,
                actions: [
                    UNNotificationAction(identifier: Self.markDoneAction, title: "Marcar como hecho", options: []),
                    UNNotificationAction(identifier: Self.snoozeAction, title: "Posponer 1 día", options: []),
                ],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    func requestAuthorizationIfNeeded(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion?(granted) }
        }
    }

    func add(_ reminder: Reminder) {
        reminders.append(reminder)
    }

    func update(_ reminder: Reminder) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[index] = reminder
    }

    func delete(_ reminder: Reminder) {
        reminders.removeAll { $0.id == reminder.id }
    }

    func setEnabled(_ isEnabled: Bool, for reminder: Reminder) {
        guard var updated = reminders.first(where: { $0.id == reminder.id }) else { return }
        updated.isEnabled = isEnabled
        update(updated)
    }

    /// Every reminder created from `templateId` — plural because the same template can be reused
    /// any number of times (e.g. several phone lines to top up or transfer from).
    func reminders(forTemplate templateId: String) -> [Reminder] {
        reminders.filter { $0.templateKey == templateId }
    }

    var customReminders: [Reminder] {
        reminders.filter { $0.templateKey == nil }
    }

    // MARK: Scheduling
    private func rescheduleAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for reminder in reminders where reminder.isEnabled {
            schedule(reminder)
        }
    }

    private func schedule(_ reminder: Reminder) {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.message
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        content.userInfo = ["reminderID": reminder.id.uuidString]

        let calendar = Calendar.current
        let request: UNNotificationRequest

        switch reminder.recurrence {
        case .none:
            let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date), repeats: false)
            request = UNNotificationRequest(identifier: reminder.id.uuidString, content: content, trigger: trigger)
        case .daily:
            let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.hour, .minute], from: reminder.date), repeats: true)
            request = UNNotificationRequest(identifier: reminder.id.uuidString, content: content, trigger: trigger)
        case .weekly:
            let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.weekday, .hour, .minute], from: reminder.date), repeats: true)
            request = UNNotificationRequest(identifier: reminder.id.uuidString, content: content, trigger: trigger)
        case .monthly:
            // iOS simply skips a month that doesn't have this day (e.g. day 31 in February) —
            // acceptable for a monthly bill/top-up reminder, which is what this is meant for.
            let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.day, .hour, .minute], from: reminder.date), repeats: true)
            request = UNNotificationRequest(identifier: reminder.id.uuidString, content: content, trigger: trigger)
        case .custom:
            // A repeating time-interval trigger fires `interval` seconds after it's *scheduled*,
            // not at `reminder.date` — iOS has no "start on this date, then repeat every N days"
            // trigger. The chosen date/time only seeds the first schedule() call; after that it
            // drifts to whenever the app last rescheduled it.
            let interval = max(60, TimeInterval(reminder.customIntervalDays) * 86400)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: true)
            request = UNNotificationRequest(identifier: reminder.id.uuidString, content: content, trigger: trigger)
        }

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Persistence
    private func save() {
        if let encoded = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(encoded, forKey: "reminders")
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: "reminders"),
           let decoded = try? JSONDecoder().decode([Reminder].self, from: data) {
            reminders = decoded
        }
    }

    // MARK: UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard let idString = response.notification.request.content.userInfo["reminderID"] as? String,
              let id = UUID(uuidString: idString),
              let reminder = reminders.first(where: { $0.id == id }) else { return }

        switch response.actionIdentifier {
        case Self.markDoneAction:
            setEnabled(false, for: reminder)
        case Self.snoozeAction:
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.message
            content.sound = .default
            content.categoryIdentifier = Self.categoryId
            content.userInfo = ["reminderID": reminder.id.uuidString]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 86400, repeats: false)
            let request = UNNotificationRequest(identifier: "\(reminder.id.uuidString)_snooze_\(UUID().uuidString)", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        default:
            DispatchQueue.main.async {
                self.deepLinkReminder = reminder
            }
        }
    }
}

// MARK: - Siri / App Intents
/// Lets Siri, Spotlight, and the Shortcuts app dial a code or place a `*99`/`#31#` call directly —
/// "Oye Siri, marca Saldo Principal en Qvacell", "Oye Siri, llama con 99 a Pepe en Qvacell".
/// Built on `AppIntents` (not legacy SiriKit `Intents.framework`), needing no separate extension target:
/// the system discovers `QvacellShortcuts` by reflection at install time. Every intent marks
/// `openAppWhenRun` so the system's own dial confirmation always has the app in the foreground to
/// appear over — nothing dials silently in the background.
enum QuickUSSDCode: String, AppEnum {
    case saldoPrincipal, bonosYPlanes, planDeDatos, saldoPospago, estadoPlanAmigo

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Código Rápido"

    static var caseDisplayRepresentations: [QuickUSSDCode: DisplayRepresentation] = [
        .saldoPrincipal: "Saldo Principal",
        .bonosYPlanes: "Bonos y Planes en USD",
        .planDeDatos: "Plan de Datos",
        .saldoPospago: "Saldo Pospago o Institucional",
        .estadoPlanAmigo: "Estado del Plan Amigos",
    ]

    /// The bundled `USSDCode.id` (`codes.json`, Home category) this quick action dials — all five
    /// are fixed, no-input codes, so there's nothing to prompt for before dialing.
    var codeId: String {
        switch self {
        case .saldoPrincipal: return "main-balance"
        case .bonosYPlanes: return "bonus-usd-plans"
        case .planDeDatos: return "data-plan"
        case .saldoPospago: return "postpaid-balance"
        case .estadoPlanAmigo: return "friends-plan-status-settings"
        }
    }
}

enum PlanCompra: String, AppEnum {
    case plan45GB, planDiario, planToDus, combo2GB, combo4GB, combo6GB, sms20, sms50, sms90, sms120, voz5min, voz10min, voz15min, voz25min, voz40min

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Plan de Compras"

    static var caseDisplayRepresentations: [PlanCompra: DisplayRepresentation] = [
        .plan45GB: "Plan de 4.5GB",
        .planDiario: "Plan Diario 200MB",
        .planToDus: "Plan ToDus",
        .combo2GB: "Combo 2GB + 15MIN + 20SMS",
        .combo4GB: "Combo 4GB + 35MIN + 40SMS",
        .combo6GB: "Combo 6GB + 60MIN + 70SMS",
        .sms20: "Plan de 20 SMS",
        .sms50: "Plan de 50 SMS",
        .sms90: "Plan de 90 SMS",
        .sms120: "Plan de 120 SMS",
        .voz5min: "Plan de 5 Minutos",
        .voz10min: "Plan de 10 Minutos",
        .voz15min: "Plan de 15 Minutos",
        .voz25min: "Plan de 25 Minutos",
        .voz40min: "Plan de 40 Minutos",
    ]

    /// Returns the base safe `code` (e.g. `*133*1*4*1#`), NOT `noConfirmCode` (`*133*1*4*1*1#`),
    /// ensuring ETECSA's native confirmation dialog appears for safety.
    var codeId: String {
        switch self {
        case .plan45GB: return "data-bundle-45gb"
        case .planDiario: return "data-daily-plan"
        case .planToDus: return "data-todus-plan"
        case .combo2GB: return "data-bundle-2gb-combo"
        case .combo4GB: return "data-bundle-4gb-combo"
        case .combo6GB: return "data-bundle-6gb-combo"
        case .sms20: return "sms-bundle-20"
        case .sms50: return "sms-bundle-50"
        case .sms90: return "sms-bundle-90"
        case .sms120: return "sms-bundle-120"
        case .voz5min: return "voice-bundle-5min"
        case .voz10min: return "voice-bundle-10min"
        case .voz15min: return "voice-bundle-15min"
        case .voz25min: return "voice-bundle-25min"
        case .voz40min: return "voice-bundle-40min"
        }
    }
}

struct EjecutarCodigoIntent: AppIntent {
    static var title: LocalizedStringResource = "Marcar Código Rápido"
    static var description = IntentDescription("Marca uno de los códigos rápidos de Qvacell: saldo, bonos, plan de datos, saldo pospago o estado del Plan Amigo.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Código")
    var codigo: QuickUSSDCode

    init() {}

    init(codigo: QuickUSSDCode) {
        self.codigo = codigo
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Marcar \(\.$codigo)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let code = USSDCodeStore().code(withId: codigo.codeId) else {
            return .result(dialog: "No se encontró ese código.")
        }
        guard await DialService.dial(code.code) else {
            return .result(dialog: "No se pudo abrir el marcador en este dispositivo.")
        }
        return .result(dialog: "Marcando \(code.localizedTitle)...")
    }
}

struct ComprarPlanIntent: AppIntent {
    static var title: LocalizedStringResource = "Comprar Plan"
    static var description = IntentDescription("Abre el marcador para comprar un plan de datos, combo, SMS o voz de ETECSA usando el código estable y seguro (con confirmación).")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Plan")
    var plan: PlanCompra

    init() {}

    init(plan: PlanCompra) {
        self.plan = plan
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Comprar \(\.$plan)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let codeObj = USSDCodeStore().code(withId: plan.codeId) else {
            return .result(dialog: "No se encontró ese plan.")
        }
        // Always dial codeObj.code (the safe code without auto-confirming *1)
        guard await DialService.dial(codeObj.code) else {
            return .result(dialog: "No se pudo abrir el marcador en este dispositivo.")
        }
        return .result(dialog: "Abriendo compra de \(codeObj.localizedTitle)...")
    }
}

struct LlamarPorCobrarIntent: AppIntent {
    static var title: LocalizedStringResource = "Llamar por Cobrar (*99)"
    static var description = IntentDescription("Marca una llamada por cobrar (*99) a un número móvil cubano usando Qvacell.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Número")
    var numero: String

    static var parameterSummary: some ParameterSummary {
        Summary("Llamar por cobrar a \(\.$numero)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let normalized = CubanPhoneNumber.normalize(numero) else {
            return .result(dialog: "Ese no parece un número móvil cubano válido.")
        }
        guard await DialService.dial("*99\(normalized)") else {
            return .result(dialog: "No se pudo abrir el marcador en este dispositivo.")
        }
        return .result(dialog: "Llamando por cobrar a \(normalized)...")
    }
}

struct LlamarOcultoIntent: AppIntent {
    static var title: LocalizedStringResource = "Llamar Oculto (#31#)"
    static var description = IntentDescription("Marca una llamada con número oculto (#31#) a un número móvil cubano usando Qvacell.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Número")
    var numero: String

    static var parameterSummary: some ParameterSummary {
        Summary("Llamar oculto a \(\.$numero)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let normalized = CubanPhoneNumber.normalize(numero) else {
            return .result(dialog: "Ese no parece un número móvil cubano válido.")
        }
        guard await DialService.dial("#31#\(normalized)") else {
            return .result(dialog: "No se pudo abrir el marcador en este dispositivo.")
        }
        return .result(dialog: "Llamando oculto a \(normalized)...")
    }
}

/// Dynamic mapping of \.applicationName:
/// In Swift, when you write phrases like "Check my balance in \(.applicationName)", iOS replaces
/// \.applicationName with the app's official name (CFBundleDisplayName, "Qvacell") — no
/// INAlternativeAppNames spoken aliases are configured, since none of the old ones ("CubaCell",
/// "Cubacel", "Cuba Cell") were ever meant to apply to a different app name.
struct QvacellShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: EjecutarCodigoIntent(),
            phrases: [
                "Marca \(\.$codigo) en \(.applicationName)",
                "Ejecuta \(\.$codigo) en \(.applicationName)",
            ],
            shortTitle: "Código Rápido",
            systemImageName: "number"
        )

        AppShortcut(
            intent: EjecutarCodigoIntent(codigo: .saldoPrincipal),
            phrases: [
                "Consulta mi saldo en \(.applicationName)",
                "Cuánto saldo tengo en \(.applicationName)",
            ],
            shortTitle: "Consultar Saldo",
            systemImageName: "banknote"
        )

        AppShortcut(
            intent: ComprarPlanIntent(),
            phrases: [
                "Compra \(\.$plan) en \(.applicationName)",
                "Comprar \(\.$plan) en \(.applicationName)",
                "Compra el \(\.$plan) en \(.applicationName)",
            ],
            shortTitle: "Comprar Plan",
            systemImageName: "cart"
        )

        AppShortcut(
            intent: LlamarPorCobrarIntent(),
            phrases: [
                "Llama por cobrar con \(.applicationName)",
                "Haz una llamada por cobrar en \(.applicationName)",
                "Llama con 99 en \(.applicationName)",
                "Llama con *99 en \(.applicationName)",
                "Llama pagando el en \(.applicationName)",
            ],
            shortTitle: "Llamar por Cobrar",
            systemImageName: "phone.arrow.up.right"
        )

        AppShortcut(
            intent: LlamarOcultoIntent(),
            phrases: [
                "Llama oculto con \(.applicationName)",
                "Haz una llamada con número oculto en \(.applicationName)",
                "Llama con privado en \(.applicationName)",
                "Llama con oculto en \(.applicationName)",
            ],
            shortTitle: "Llamar Oculto",
            systemImageName: "eye.slash"
        )
    }
}


