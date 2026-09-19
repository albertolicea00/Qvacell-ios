import Foundation

/// One entry the CallerIDExtension registers with CallKit: a `*99` collect-call's wrapped
/// caller ID (see `CallerIDStore.wrappedNumber`) mapped to the real contact's name.
struct CallerIDEntry: Codable {
    let wrappedNumber: Int64
    let name: String
}

/// Shared between the main app (which builds the identification list from the device's
/// Contacts) and CallerIDExtension (a CallKit Call Directory Extension that only reads it) via
/// an App Group container — a Call Directory Extension runs in its own sandboxed process and
/// has no Contacts access of its own.
enum CallerIDStore {
    static let appGroupID = "group.com.qvacell.shared"
    static let extensionBundleID = "com.qvacell.app.CallerIDExtension"

    private static let fileName = "caller-id-entries.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    static func write(_ entries: [CallerIDEntry]) {
        guard let url = fileURL else { return }
        let sorted = entries.sorted { $0.wrappedNumber < $1.wrappedNumber }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> [CallerIDEntry] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([CallerIDEntry].self, from: data)) ?? []
    }

    /// ETECSA's `*99` collect-call service shows the incoming caller ID wrapped as
    /// `99` + country code (`53`) + the 8-digit local number + `99` — e.g. `51234567`
    /// becomes `99535123456799`. `localNumber` must already be the normalized 8-digit form
    /// `ContactsService` stores (country code stripped).
    static func wrappedNumber(forLocalNumber localNumber: String) -> Int64? {
        Int64("99" + "53" + localNumber + "99")
    }
}
