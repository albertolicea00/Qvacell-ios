import CallKit
import MessageUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Home Screen

/// Root screen. Tab order is explicit (not a generic `ForEach` over every category) since Home
/// must sit in the middle, flanked by Contactos/Líneas de Ayuda on one side and Compras on the
/// other: Líneas de Ayuda, Contactos, Home, Compras, Ajustes.
struct HomeView: View {
    @Environment(USSDCodeStore.self) private var store
    @Environment(AccentColorStore.self) private var accentColorStore
    @Environment(ReminderManager.self) private var reminderManager
    @Environment(TabRouter.self) private var tabRouter
    @AppStorage("defaultTab") private var defaultTab = HomeTab.home.rawValue
    @State private var selectedTab = HomeTab.home.rawValue

    var body: some View {
        TabView(selection: $selectedTab) {
            if let helplines = store.tabCategories.first(where: { $0.id == "helplines" }) {
                CategoryListView(category: helplines)
                    .tabItem {
                        Label("Ayuda", systemImage: helplines.icon)
                    }
                    .tag(HomeTab.helplines.rawValue)
            }

            ContactsListView()
                .tabItem {
                    Label("Contactos", systemImage: "person.crop.circle.fill")
                }
                .tag(HomeTab.contacts.rawValue)

            HomeQuickActionsView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(HomeTab.home.rawValue)

            if let purchase = store.tabCategories.first(where: { $0.id == "purchase" }) {
                CategoryListView(category: purchase)
                    .tabItem {
                        Label("Compras", systemImage: purchase.icon)
                    }
                    .tag(HomeTab.purchase.rawValue)
            }

            SettingsView()
                .tabItem {
                    Label("Ajustes", systemImage: "gearshape.fill")
                }
                .tag(HomeTab.settings.rawValue)
        }
        .tint(accentColorStore.color)
        .onAppear {
            selectedTab = (HomeTab(rawValue: defaultTab) ?? .home).tabToSelect.rawValue
        }
        .onChange(of: tabRouter.pendingTab) { _, newTab in
            guard let newTab else { return }
            selectedTab = newTab.rawValue
            tabRouter.pendingTab = nil
        }
        // Notification tap lands here regardless of which tab was showing.
        .sheet(item: Binding(
            get: { reminderManager.deepLinkReminder },
            set: { reminderManager.deepLinkReminder = $0 }
        )) { reminder in
            ReminderDetailView(reminder: reminder)
        }
    }
}

/// The 5 tabs, keyed by a stable string so it can be stored in `@AppStorage` (as "Pestaña
/// inicial" in Ajustes › Preferencias) and used as the `TabView` selection tag.
enum HomeTab: String, CaseIterable, Identifiable {
    case helplines, contacts, home, purchase, settings, smsServices, directory, database

    var id: String { rawValue }

    /// Every case except the plain `.settings` landing screen itself (and `.database` if locked) —
    /// used by "Pestaña Inicial" in Ajustes.
    static func launchOptions(includingDatabase: Bool = false) -> [HomeTab] {
        allCases.filter { $0 != .settings && ($0 != .database || includingDatabase) }
    }

    var displayName: LocalizedStringKey {
        switch self {
            case .helplines: return "Líneas de Ayuda"
            case .contacts: return "Contactos"
            case .home: return "Home"
            case .purchase: return "Compras"
            case .smsServices: return "Servicios por SMS"
            case .settings: return "Ajustes"
            case .directory: return "Buscar en Directorio"
            case .database: return "Buscar en Database"
        }
    }

    /// The actual `TabView` tab to select for this launch destination — none of these nested
    /// Ajustes screens are tabs themselves, they're screens `SettingsView` pushes onto once
    /// Ajustes is showing.
    var tabToSelect: HomeTab {
        switch self {
        case .database, .smsServices, .directory: return .settings
        default: return self
        }
    }
}

#Preview {
    HomeView()
        .environment(USSDCodeStore())
        .environment(AccentColorStore())
}

// MARK: - Home Quick Actions

/// The Home tab: one system `List` (same `.insetGrouped` style as every other tab), with
/// "Consultar Todo" and the balance shortcuts sharing a single "Saldo y Planes" section,
/// plus a "Transferir" and a "Recargar" section whose fields are plain rows, not a custom card.
struct HomeQuickActionsView: View {
    @Environment(USSDCodeStore.self) private var store
    @Environment(AccentColorStore.self) private var accentColorStore
    @AppStorage("showNetworkStatus") private var showNetworkStatus = false

    @State private var phoneNumber = ""
    @State private var pin = ""
    @State private var amount = ""
    @State private var cardNumber = ""
    @State private var showingContactPicker = false
    @State private var showsInvalidNumberWarning = false

    /// `true` while `pin` holds the value just loaded from `TransferPinStore` and not yet typed
    /// over by the user — drives whether the "Clave" field masks itself (see `PinRevealField`).
    @State private var pinIsFromStore = false
    /// Set right before assigning `pin` from the store so the `onChange(of: pin)` below can tell
    /// that mutation apart from the user actually typing, instead of immediately unmasking it.
    @State private var isLoadingStoredPin = false

    private var isTransferDisabled: Bool {
        phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty
            || pin.trimmingCharacters(in: .whitespaces).isEmpty
            || amount.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isRechargeDisabled: Bool {
        cardNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showNetworkStatus {
                    ConnectionBannerView()
                }

                List {
                    Section("Consultas") {
                        QuickActionTileGrid(tiles: [
                            ("Saldo", "creditcard.fill", "main-balance"),
                            ("Datos", "antenna.radiowaves.left.and.right", "data-plan"),
                            ("Voz", "phone.fill", "voice-balance"),
                            ("SMS", "message.fill", "sms-balance"),
                            ("Límite", "creditcard.trianglebadge.exclamationmark", "national-recharge-limit"),
                            ("Amigo", "person.2.fill", "friends-plan"),
                            ("Bono", "gift.fill", "bonus-usd-plans"),
                            ("Pospago", "building.2.fill", "postpaid-balance"),
                        ], dial: dial)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                    }
                    .listSectionSpacing(6)

                    Section {
                        HStack(spacing: 12) {
                            Button {
                                showingContactPicker = true
                            } label: {
                                Image(systemName: "person.crop.circle")
                                    .foregroundStyle(.secondary)
                            }

                            TextField("Número (+53 ...)", text: $phoneNumber)
                                .keyboardType(.numberPad)
                        }

                        HStack(spacing: 12) {
                            PinRevealField(title: "Clave", text: $pin, isMasked: pinIsFromStore)
                            Divider()
                            TextField("Monto", text: $amount)
                                .keyboardType(.numberPad)
                        }

                        Button {
                            dialTransfer()
                        } label: {
                            HStack(spacing: 6) {
                                Spacer()
                                Text("Transferir")
                                Image(systemName: "arrow.right")
                            }
                        }
                        .disabled(isTransferDisabled)
                    } header: {
                        Text("Transferir")
                    }

                    Section("Recargar") {
                        Button {
                            dial(codeId: "recharge-call")
                        } label: {
                            HStack {
                                Label("Recargar por Llamada", systemImage: "phone.fill")
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                        }
                    }
                    .listSectionSpacing(6)

                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Escanear (próximamente)")

                            TextField("Código de recarga", text: $cardNumber)
                                .keyboardType(.numberPad)
                        }

                        Button {
                            dialRechargeCard()
                        } label: {
                            HStack(spacing: 6) {
                                Spacer()
                                Text("Recargar con Tarjeta")
                                Image(systemName: "arrow.right")
                            }
                        }
                        .disabled(isRechargeDisabled)
                    }
                    .listSectionSpacing(6)

                    if let advanceBalanceGroup = store.group(named: "Servicio Adelanta Saldo") {
                        Section(advanceBalanceGroup.localizedName ?? "") {
                            HStack(spacing: 12) {
                                ForEach(advanceBalanceGroup.codes) { code in
                                    Button {
                                        DialService.dial(code.code)
                                    } label: {
                                        Text(code.price ?? code.localizedTitle)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(OutlineButtonStyle())
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .tint(accentColorStore.color)
                .sheet(isPresented: $showingContactPicker) {
                    ContactPickerView { number, isValidCubanNumber in
                        phoneNumber = number
                        showsInvalidNumberWarning = !isValidCubanNumber
                    }
                    .ignoresSafeArea()
                }
                .alert("Número no parece cubano", isPresented: $showsInvalidNumberWarning) {
                    Button("Entendido", role: .cancel) {}
                } message: {
                    Text("Este contacto no tiene un número con formato de móvil cubano (+53 y 8 dígitos). Revísalo antes de transferir.")
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if pin.isEmpty, let saved = TransferPinStore.load() {
                isLoadingStoredPin = true
                pin = saved
            }
        }
        .onChange(of: pin) {
            if isLoadingStoredPin {
                pinIsFromStore = true
                isLoadingStoredPin = false
            } else {
                pinIsFromStore = false
            }
        }
    }

    private func dial(codeId: String) {
        if let code = store.code(withId: codeId) {
            DialService.dial(code.code)
        }
    }

    /// Composes `transfer-direct`'s `{phoneNumber}`/`{pin}`/`{amount}` placeholders. Assumed dial
    /// pattern `*234*1*{phoneNumber}*{pin}*{amount}#` — verify against the real ETECSA menu before
    /// relying on it; this app has no way to confirm it against a live line.
    private func dialTransfer() {
        guard let code = store.code(withId: "transfer-direct") else { return }
        let resolved = code.resolvedCode(with: ["phoneNumber": phoneNumber, "pin": pin, "amount": amount])
        DialService.dial(resolved)
    }

    private func dialRechargeCard() {
        guard let code = store.code(withId: "recharge-card") else { return }
        DialService.dial(code.resolvedCode(input: cardNumber))
    }
}

#Preview {
    HomeQuickActionsView()
        .environment(USSDCodeStore())
        .environment(AccentColorStore())
}

/// A secondary/outline look: border and text in the tint color, no filled background —
/// unlike `.bordered`, which fills with a light tint. Used for the Adelanta Saldo amount buttons.
private struct OutlineButtonStyle: ButtonStyle {
    @Environment(AccentColorStore.self) private var accentColorStore

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 6)
            .foregroundStyle(accentColorStore.color)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(accentColorStore.color, lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// One square icon + label button in the Home quick-action grid.
private struct QuickActionTile: View {
    let title: LocalizedStringKey
    let systemImage: String
    /// Explicit width computed by the parent from the available screen width, so the tile
    /// actually grows on a bigger screen instead of collapsing to the icon's intrinsic size.
    let size: CGFloat
    let action: () -> Void

    @Environment(AccentColorStore.self) private var accentColorStore
    /// 0 = filled (colored background, white icon/text), 1 = outline (transparent background,
    /// colored border/icon/text) — set in Ajustes › Preferencias.
    @AppStorage("quickActionTileStyle") private var style: Int = 0

    private var isOutline: Bool { style == 1 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.24))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isOutline ? accentColorStore.color : Color.white)
            .frame(width: size, height: size)
            .background(
                isOutline ? Color.clear : accentColorStore.color,
                in: RoundedRectangle(cornerRadius: size * 0.2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.2)
                    .stroke(accentColorStore.color, lineWidth: isOutline ? 1.5 : 0)
            )
        }
        .buttonStyle(.plain)
    }
}

/// `QuickActionTile`s laid out 4-per-row, wrapping to as many rows as needed — used for the
/// "Consultas" section on Home.
private struct QuickActionTileGrid: View {
    let tiles: [(LocalizedStringKey, String, String)]
    let dial: (String) -> Void

    private let columns = 4
    private let gap: CGFloat = 16

    private var rowCount: Int { (tiles.count + columns - 1) / columns }

    var body: some View {
        GeometryReader { geometry in
            let rawSize = (geometry.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let tileSize = min(max(rawSize, 44), 84)

            VStack(spacing: gap) {
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < tiles.count {
                                let (title, icon, codeId) = tiles[index]
                                QuickActionTile(title: title, systemImage: icon, size: tileSize) {
                                    dial(codeId)
                                }
                            } else {
                                Color.clear.frame(width: tileSize, height: tileSize)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: CGFloat(rowCount) * 84 + CGFloat(rowCount - 1) * gap)
    }
}

// MARK: - Contacts Screen

/// Contactos tab: the device's own address book, listed alphabetically with a search bar —
/// each row gets two extra call buttons (collect call via `*99`, hidden-number call via `#31#`)
/// instead of a single generic "call" action, since that's the whole point of this screen.
struct ContactsListView: View {
    @State private var service = ContactsService()
    @State private var searchText = ""
    @Environment(AccentColorStore.self) private var accentColorStore
    @Environment(\.scenePhase) private var scenePhase

    /// One row per Cuban number, not per contact — a contact with several lines shows up as
    /// several rows, each tagged with its own label ("móvil", "trabajo", "iPhone"...), same as
    /// how the system Phone/Contacts apps let you pick a specific number.
    private var entries: [ContactListEntry] {
        service.contacts.flatMap { contact in
            contact.numbers.map { ContactListEntry(contact: contact, number: $0) }
        }
    }

    private var filteredEntries: [ContactListEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter { entry in
            entry.contact.name.localizedCaseInsensitiveContains(searchText)
                || entry.number.number.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Grouped by first letter of contact name, sorted A→Z — no side index strip, just
    /// section headers plus the search bar to narrow things down.
    private var groupedEntries: [(letter: String, entries: [ContactListEntry])] {
        let groups = Dictionary(grouping: filteredEntries) { entry in
            String(entry.contact.name.prefix(1)).uppercased()
        }
        return groups.keys.sorted().map { letter in
            (letter, groups[letter]!.sorted {
                $0.contact.name.localizedCaseInsensitiveCompare($1.contact.name) == .orderedAscending
            })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if service.isDenied {
                    VStack(spacing: 20) {
                        ContentUnavailableView(
                            "Sin Acceso a Contactos",
                            systemImage: "person.crop.circle.badge.exclamationmark",
                            description: Text("Activa el permiso de Contactos para poder llamar o transferir saldo a tus contactos directamente.")
                        )

                        VStack(spacing: 0) {
                            DirectoryActionRow(
                                title: "Permitir Acceso a Contactos",
                                systemImage: "person.crop.circle.badge.checkmark",
                                isEnabled: true,
                                tint: accentColorStore.color
                            ) {
                                service.requestAccess()
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !service.isLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if service.contacts.isEmpty {
                    ContentUnavailableView(
                        "Sin Contactos Cubanos",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("No se encontró ningún contacto con número cubano (+53, 8 dígitos).")
                    )
                } else {
                    List {
                        ForEach(groupedEntries, id: \.letter) { group in
                            Section(group.letter) {
                                ForEach(group.entries) { entry in
                                    ContactCallRowView(entry: entry)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Buscar")
                    .searchDictationBehavior(.automatic)
                }
            }
            .navigationTitle("Contactos")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { service.reload() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                service.reload()
            }
        }
    }
}

/// One contact + one of its Cuban numbers — a contact with several lines yields several
/// entries, one per row, each independently callable/identifiable.
private struct ContactListEntry: Identifiable, Hashable {
    let contact: DeviceContact
    let number: ContactPhoneNumber

    var id: String { "\(contact.id)-\(number.number)" }
}

/// One row per contact number: name + labeled number ("móvil: 5XXXXXXX"). Swiping reveals a
/// call action on each side — collect call (`*99`) trailing, hidden caller ID (`#31#`)
/// leading — and tapping the row opens a bottom sheet with both choices, mirroring the old
/// Llamada por Cobrar / Llamada Privada codes, just applied directly to this number.
private struct ContactCallRowView: View {
    let entry: ContactListEntry

    @Environment(AccentColorStore.self) private var accentColorStore
    @State private var showingCallOptions = false

    private var number: String { entry.number.number }

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatarView(contact: entry.contact)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.contact.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.appForeground)
                (Text(number).font(AppTheme.codeFont(size: 14))
                    + Text(entry.contact.numbers.count > 1 ? " (\(entry.number.label))" : "")
                        .font(.caption)
                        .italic())
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            showingCallOptions = true
        }
        .swipeActions(edge: .trailing) {
            Button {
                DialService.dial("*99\(number)")
            } label: {
                Label("Llamar 99", systemImage: "phone.fill")
            }
            .tint(accentColorStore.color)

            Button {
                DialService.dial("#31#\(number)")
            } label: {
                Label("Anónimo", systemImage: "shield.lefthalf.filled")
            }
            .tint(accentColorStore.color.opacity(0.6))
        }
        .sheet(isPresented: $showingCallOptions) {
            ContactCallOptionsSheet(entry: entry)
        }
    }
}

/// Round contact photo pulled from the device address book, falling back to the contact's
/// initials on a tinted circle when there's no photo.
private struct ContactAvatarView: View {
    let contact: DeviceContact
    var size: CGFloat = 40

    @Environment(AccentColorStore.self) private var accentColorStore
    @State private var uiImage: UIImage?

    private var initials: String {
        let words = contact.name.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    accentColorStore.color.opacity(0.2)
                    Text(initials)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(accentColorStore.color)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: contact.id) {
            uiImage = await ContactThumbnailLoader.thumbnail(forContactID: contact.id)
        }
    }
}

/// Bottom sheet shown when a contact row is tapped: call the contact (collect via `*99` or
/// hidden caller ID via `#31#`), or transfer balance to it — same Clave/Monto form as Home's
/// Transferir, just with the number already filled in from the contact.
private struct ContactCallOptionsSheet: View {
    let entry: ContactListEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(USSDCodeStore.self) private var store
    @Environment(AccentColorStore.self) private var accentColorStore

    @State private var pin = ""
    @State private var amount = ""

    /// Same store-vs-typed tracking as Home's Transferir — see `HomeQuickActionsView`.
    @State private var pinIsFromStore = false
    @State private var isLoadingStoredPin = false

    private var contact: DeviceContact { entry.contact }
    private var number: String { entry.number.number }

    private var isTransferDisabled: Bool {
        pin.trimmingCharacters(in: .whitespaces).isEmpty
            || amount.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    ContactAvatarView(contact: contact, size: 54)

                    VStack(spacing: 2) {
                        Text(contact.name)
                            .font(.title2.weight(.semibold))
                        (Text(number).font(AppTheme.codeFont(size: 16))
                            + Text(entry.contact.numbers.count > 1 ? " (\(entry.number.label))" : "")
                                .font(.subheadline)
                                .italic())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                VStack(spacing: 10) {
                    Button {
                        DialService.dial("*99\(number)")
                        dismiss()
                    } label: {
                        Label("Llamar con *99", systemImage: "phone.fill")
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColorStore.color)

                    Button {
                        DialService.dial("#31#\(number)")
                        dismiss()
                    } label: {
                        Label("Llamar Anónimo", systemImage: "shield.lefthalf.filled")
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(accentColorStore.color)
                }
                .controlSize(.large)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listSectionSpacing(6)

            Section("Transferir Saldo") {
                HStack(spacing: 12) {
                    PinRevealField(title: "Clave", text: $pin, isMasked: pinIsFromStore)
                    Divider()
                    TextField("Monto", text: $amount)
                        .keyboardType(.numberPad)
                }

                Button {
                    dialTransfer()
                } label: {
                    HStack(spacing: 6) {
                        Spacer()
                        Text("Transferir")
                        Image(systemName: "arrow.right")
                    }
                }
                .disabled(isTransferDisabled)
            }

            Section {
                if let addFriendCode = store.code(withId: "friends-plan-add-member") {
                    Button {
                        dialFriendsPlan(addFriendCode)
                    } label: {
                        HStack {
                            Text("Agregar a mi Plan de Amigos")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .foregroundStyle(accentColorStore.color)
                    }
                    .disabled(addFriendCode.code.isEmpty)
                }

                if let removeFriendCode = store.code(withId: "friends-plan-remove-member") {
                    Button {
                        dialFriendsPlan(removeFriendCode)
                    } label: {
                        HStack {
                            Text("Eliminar de mi Plan de Amigos")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .foregroundStyle(accentColorStore.color)
                    }
                    .disabled(removeFriendCode.code.isEmpty)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            if pin.isEmpty, let saved = TransferPinStore.load() {
                isLoadingStoredPin = true
                pin = saved
            }
        }
        .onChange(of: pin) {
            if isLoadingStoredPin {
                pinIsFromStore = true
                isLoadingStoredPin = false
            } else {
                pinIsFromStore = false
            }
        }
    }

    /// Composes `transfer-direct`'s `{phoneNumber}`/`{pin}`/`{amount}` placeholders — same as
    /// Home's Transferir, with the contact's number already supplied.
    private func dialTransfer() {
        guard let code = store.code(withId: "transfer-direct") else { return }
        let resolved = code.resolvedCode(with: ["phoneNumber": number, "pin": pin, "amount": amount])
        DialService.dial(resolved)
        dismiss()
    }

    private func dialFriendsPlan(_ code: USSDCode) {
        guard !code.code.isEmpty else { return }
        DialService.dial(code.resolvedCode(input: number))
        dismiss()
    }
}

// MARK: - Category Screen

/// One tab's content: the codes belonging to a single category.
/// Tapping a row dials it directly — iOS itself confirms before the call is placed.
/// Codes that need an extra value (card number, phone number, ...) prompt for it first via an alert.
struct CategoryListView: View {
    let category: USSDCategory

    @Environment(AccentColorStore.self) private var accentColorStore
    @Environment(USSDCodeStore.self) private var store
    @AppStorage("showNetworkStatus") private var showNetworkStatus = false
    @AppStorage("quickPurchaseNoConfirmDefault") private var quickPurchaseNoConfirmDefault = false
    @State private var pendingInputCode: USSDCode?
    @State private var inputText = ""
    @State private var searchText = ""
    /// Compras-only, and never persisted itself — it just starts out matching
    /// `quickPurchaseNoConfirmDefault` each time this view is (re)created, i.e. on every fresh app
    /// launch, per "Activar por Defecto..." in Ajustes.
    @State private var isQuickActionEnabled = false

    /// `category.groups`, narrowed to codes whose title or number matches the search text —
    /// empty groups are dropped so an unmatched group doesn't leave a bare header behind.
    private var filteredGroups: [USSDCodeGroup] {
        guard !searchText.isEmpty else { return category.groups }
        return category.groups.compactMap { group in
            let matches = group.codes.filter {
                $0.localizedTitle.localizedCaseInsensitiveContains(searchText)
                    || $0.code.localizedCaseInsensitiveContains(searchText)
            }
            guard !matches.isEmpty else { return nil }
            return USSDCodeGroup(name: group.name, codes: matches)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showNetworkStatus {
                    ConnectionBannerView()
                }
                if category.id == "purchase" && isQuickActionEnabled {
                    QuickPurchaseWarningBannerView()
                }

                List {
                    if category.id == "purchase" {
                        Section {
                            Toggle("Acción sin Confirmación", isOn: $isQuickActionEnabled)
                        } footer: {
                            Text("Marca el código saltando el paso de confirmación de ETECSA, por si acaso confías en la selección y quieres ahorrarte un paso.")
                        }
                    }

                    ForEach(filteredGroups) { group in
                        Section {
                            ForEach(group.codes) { code in
                                // Same compact row for anything with an icon, a price, or the
                                // explicit `compact` flag — an icon-less code still gets this row
                                // shape (just without a leading icon), not the old
                                // title+description+badge row.
                                if code.showsNumber == true {
                                    ContactRowView(code: code) { select(code) }
                                        .contentShape(Rectangle())
                                        .onTapGesture { select(code) }
                                } else if code.icon != nil || code.price != nil || code.compact == true {
                                    Button {
                                        select(code)
                                    } label: {
                                        HStack {
                                            if let icon = code.icon {
                                                Label(code.localizedTitle, systemImage: icon)
                                            } else {
                                                Text(code.localizedTitle)
                                            }
                                            if category.id == "purchase" {
                                                Spacer()
                                                if let price = code.price {
                                                    Text(price)
                                                        .font(.subheadline.weight(.semibold))
                                                        .foregroundStyle(.secondary)
                                                }
                                                Image(systemName: "arrow.right")
                                            } else if let price = code.price {
                                                Spacer()
                                                Text(price)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                } else {
                                    CodeRowView(code: code)
                                        .contentShape(Rectangle())
                                        .onTapGesture { select(code) }
                                }
                            }
                        } header: {
                            if let name = group.localizedName {
                                Text(name)
                            } else {
                                // A little breathing room in place of a missing header, so an
                                // unnamed first section doesn't sit flush against the nav bar.
                                Color.clear.frame(height: 8)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .tint(accentColorStore.color)
                .searchable(text: $searchText, prompt: "Buscar")
                .searchDictationBehavior(.automatic)
            }
            .navigationTitle(category.localizedName)
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                pendingInputCode?.localizedTitle ?? "",
                isPresented: Binding(
                    get: { pendingInputCode != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingInputCode = nil
                            inputText = ""
                        }
                    }
                ),
                presenting: pendingInputCode
            ) { code in
                TextField(code.inputPlaceholder ?? "Dato", text: $inputText)
                    .keyboardType(.phonePad)
                Button("Marcar") { dial(code, input: inputText) }
                Button("Cancelar", role: .cancel) {}
            } message: { code in
                Text(code.localizedDetails)
            }
        }
        .onAppear {
            if category.id == "purchase" {
                isQuickActionEnabled = quickPurchaseNoConfirmDefault
            }
        }
    }

    /// The code actually dialed — `noConfirmCode` (which auto-selects ETECSA's confirmation step)
    /// only when Acción sin Confirmación is on for this code, otherwise the normal `code`.
    private func dialCode(for code: USSDCode) -> String {
        guard category.id == "purchase", isQuickActionEnabled, let noConfirmCode = code.noConfirmCode else {
            return code.code
        }
        return noConfirmCode
    }

    private func select(_ code: USSDCode) {
        if code.requiresInput {
            inputText = ""
            pendingInputCode = code
        } else {
            DialService.dial(dialCode(for: code))
        }
    }

    private func dial(_ code: USSDCode, input: String) {
        DialService.dial(code.resolvedCode(input: input))
    }
}

// MARK: - SMS Subscriptions

/// Ajustes › Servicios por SMS — subscribe/unsubscribe USSD codes for ETECSA's SMS info
/// services, pulled from the "Servicios por SMS" group in `codes.json` (currently empty; codes
/// go straight into the JSON once they're in hand, same as every other code in the app — never
/// hardcoded here).
/// Ajustes › Utilidades › Servicios por SMS — every SMS-based service except "Configuraciones"
/// (LTE, IMEI/3G-4G check, MMS setup — those render directly as their own rows under Ajustes ›
/// Cuenta instead, see `SettingsView`, since they're quick one-off device/line settings, not
/// something worth another level of navigation here). Deportes (Pelota Cubana, MLB, and the
/// football tournaments) sits as its own Section, between DHL y Vuelos and Noticias.
struct SMSServicesView: View {
    var body: some View {
        SMSCodeListView(
            title: "Servicios por SMS",
            groupNames: [
                "Consultas", "Tarifas y Servicios", "DHL y Vuelos", "Deportes", "Noticias",
                "Recetas, Frases y Horóscopos",
            ],
            emptyStateDescription: "Los códigos de suscripción de SMS se agregarán aquí próximamente."
        )
    }
}

/// Shared list/compose logic behind `SMSServicesView` — renders the given
/// `codes.json` groups in the same compact, price-trailing row shape as Compras, and handles
/// composing the SMS itself (the requires-input alert, the `MFMessageComposeViewController` sheet,
/// and the "this device can't send texts" guard, e.g. the Simulator). `extraSection` is a fixed
/// slot between `leadingGroupNames` and `trailingGroupNames` for a non-code row like the Deportes
/// nav link — most callers don't need one, see the `EmptyView` convenience init below.
private struct SMSCodeListView<ExtraSection: View>: View {
    let title: LocalizedStringKey
    let leadingGroupNames: [String]
    var trailingGroupNames: [String] = []
    let emptyStateDescription: LocalizedStringKey
    let extraSection: () -> ExtraSection

    @Environment(USSDCodeStore.self) private var store
    @Environment(AccentColorStore.self) private var accentColorStore

    @State private var pendingInputCode: USSDCode?
    @State private var inputText = ""
    @State private var pendingSMS: PendingSMS?
    @State private var showsCannotSendTextAlert = false
    @State private var variantPickerCode: USSDCode?
    @State private var searchText = ""

    private var leadingGroups: [USSDCodeGroup] { leadingGroupNames.compactMap { store.group(named: $0) } }
    private var trailingGroups: [USSDCodeGroup] { trailingGroupNames.compactMap { store.group(named: $0) } }

    private var hasAnyCodes: Bool {
        (leadingGroups + trailingGroups).contains { !$0.codes.isEmpty }
    }

    /// Groups narrowed to codes whose title matches the search text — empty groups are dropped so
    /// an unmatched group doesn't leave a bare header behind, same pattern as `CategoryListView`.
    private func filtered(_ groups: [USSDCodeGroup]) -> [USSDCodeGroup] {
        guard !searchText.isEmpty else { return groups }
        return groups.compactMap { group in
            let matches = group.codes.filter { $0.localizedTitle.localizedCaseInsensitiveContains(searchText) }
            guard !matches.isEmpty else { return nil }
            return USSDCodeGroup(name: group.name, codes: matches)
        }
    }

    var body: some View {
        Group {
            if !hasAnyCodes {
                ContentUnavailableView(
                    "Sin Códigos Todavía",
                    systemImage: "envelope.badge",
                    description: Text(emptyStateDescription)
                )
            } else {
                List {
                    codeSections(filtered(leadingGroups))
                    if searchText.isEmpty {
                        extraSection()
                    }
                    codeSections(filtered(trailingGroups))
                }
                .listStyle(.insetGrouped)
                .tint(accentColorStore.color)
                .searchable(text: $searchText, prompt: "Buscar")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            pendingInputCode?.localizedTitle ?? "",
            isPresented: Binding(
                get: { pendingInputCode != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingInputCode = nil
                        inputText = ""
                    }
                }
            ),
            presenting: pendingInputCode
        ) { code in
            TextField(code.inputPlaceholder ?? "Dato", text: $inputText)
                .keyboardType(.phonePad)
            Button("Continuar") { composeSMS(code, input: inputText) }
            Button("Cancelar", role: .cancel) {}
        } message: { code in
            Text(code.localizedDetails)
        }
        .alert("No se Puede Enviar SMS", isPresented: $showsCannotSendTextAlert) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("Este dispositivo no puede enviar mensajes de texto (por ejemplo, el Simulador de Xcode no soporta SMS).")
        }
        .confirmationDialog(
            variantPickerCode?.localizedTitle ?? "",
            isPresented: Binding(
                get: { variantPickerCode != nil },
                set: { if !$0 { variantPickerCode = nil } }
            ),
            titleVisibility: .visible,
            presenting: variantPickerCode
        ) { code in
            ForEach(code.variants ?? [], id: \.label) { variant in
                Button(variant.localizedLabel) { composeVariant(code, variant) }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .sheet(item: $pendingSMS) { pending in
            MessageComposeView(recipient: pending.recipient, body: pending.body)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func codeSections(_ groups: [USSDCodeGroup]) -> some View {
        ForEach(groups) { group in
            if !group.codes.isEmpty {
                Section(group.localizedName ?? "") {
                    ForEach(group.codes) { code in
                        // Same compact, price-trailing row shape as Compras — set
                        // "compact": true on every code here so they all render like it, price or
                        // not. `variants` (a couple of named choices, e.g. Bundesliga's
                        // Resultados/Posiciones/Goleadores) opens a confirmation dialog; `options`
                        // (a bigger, searchable set, e.g. Frases y Poemas' ~35 topics) opens a full
                        // picker screen instead.
                        if code.variants != nil {
                            Button {
                                variantPickerCode = code
                            } label: {
                                rowLabel(code)
                            }
                        } else if code.options != nil {
                            NavigationLink {
                                SMSOptionPickerView(code: code)
                            } label: {
                                rowLabel(code)
                            }
                        } else {
                            Button {
                                select(code)
                            } label: {
                                rowLabel(code)
                            }
                        }
                    }
                }
            }
        }
    }

    private func select(_ code: USSDCode) {
        if code.requiresInput {
            inputText = ""
            pendingInputCode = code
        } else {
            composeSMS(code, input: "")
        }
    }

    private func composeSMS(_ code: USSDCode, input: String) {
        guard MFMessageComposeViewController.canSendText() else {
            showsCannotSendTextAlert = true
            return
        }
        pendingSMS = PendingSMS(recipient: code.code, body: code.resolvedSMSBody(input: input))
    }

    private func composeVariant(_ code: USSDCode, _ variant: SMSVariant) {
        guard MFMessageComposeViewController.canSendText() else {
            showsCannotSendTextAlert = true
            return
        }
        pendingSMS = PendingSMS(recipient: code.code, body: variant.smsBody)
    }

    @ViewBuilder
    private func rowLabel(_ code: USSDCode) -> some View {
        HStack {
            Text(code.localizedTitle)
            if code.isSubscription == true {
                Text("Suscripción")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // `options` codes push to `SMSOptionPickerView` as a `NavigationLink` — that already
            // gets its own system d#imageLiteral(resourceName: "simulator_screenshot_68190E19-D612-44BD-B6BE-D8DDEF455C7D.png")isclosure chevron, and the price varies per option shown
            // inside there, not here, so this row skips both instead of doubling up.
            if code.options == nil {
                if let price = code.price {
                    Text(price)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.right")
            }
        }
    }
}

extension SMSCodeListView where ExtraSection == EmptyView {
    init(title: LocalizedStringKey, groupNames: [String], emptyStateDescription: LocalizedStringKey) {
        self.init(
            title: title,
            leadingGroupNames: groupNames,
            trailingGroupNames: [],
            emptyStateDescription: emptyStateDescription,
            extraSection: { EmptyView() }
        )
    }
}

/// Picker for an SMS code with a fixed set of valid message texts (`code.options`, e.g. "Frases y
/// Poemas" — texting one of ~35 topic words to 8888 gets a phrase back for that topic). Picking a
/// row sends it verbatim as the SMS body. A search bar filters the list, and typing something that
/// doesn't match any known option offers sending exactly what was typed instead — the list isn't
/// necessarily exhaustive, so this doesn't hard-block anything outside it.
private struct SMSOptionPickerView: View {
    let code: USSDCode

    @State private var searchText = ""
    @State private var pendingSMS: PendingSMS?
    @State private var showsCannotSendTextAlert = false

    private var allOptions: [String] { code.options ?? [] }

    private var filteredOptions: [String] {
        guard !searchText.isEmpty else { return allOptions }
        return allOptions.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    /// True once something's typed that isn't an exact match for a known option — offers sending
    /// it as a custom value instead of restricting to the list.
    private var showsCustomOption: Bool {
        !trimmedSearch.isEmpty && !allOptions.contains { $0.caseInsensitiveCompare(trimmedSearch) == .orderedSame }
    }

    var body: some View {
        List {
            if showsCustomOption {
                Section {
                    Button {
                        send(trimmedSearch.uppercased())
                    } label: {
                        HStack {
                            Text("Enviar \"\(trimmedSearch)\"")
                            Spacer()
                            if let price = code.price {
                                Text(price)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "arrow.right")
                        }
                    }
                } footer: {
                    Text("No es uno de los temas conocidos — se enviará tal cual lo escribiste.")
                }
            }

            ForEach(filteredOptions, id: \.self) { option in
                Button {
                    send(option)
                } label: {
                    HStack {
                        Text(option.capitalized)
                        Spacer()
                        if let price = code.price {
                            Text(price)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "arrow.right")
                    }
                }
            }
        }
        .navigationTitle(code.localizedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Buscar o escribir uno nuevo")
        .alert("No se Puede Enviar SMS", isPresented: $showsCannotSendTextAlert) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("Este dispositivo no puede enviar mensajes de texto (por ejemplo, el Simulador de Xcode no soporta SMS).")
        }
        .sheet(item: $pendingSMS) { pending in
            MessageComposeView(recipient: pending.recipient, body: pending.body)
                .ignoresSafeArea()
        }
    }

    private func send(_ option: String) {
        guard MFMessageComposeViewController.canSendText() else {
            showsCannotSendTextAlert = true
            return
        }
        pendingSMS = PendingSMS(recipient: code.code, body: code.resolvedSMSBody(input: option))
    }
}

/// `MessageComposeView`'s `.sheet(item:)` payload — recipient + body resolved once, right before
/// presenting, so the sheet doesn't need its own access back into `USSDCode`/placeholder logic.
private struct PendingSMS: Identifiable {
    let id = UUID()
    let recipient: String
    let body: String
}

#Preview {
    NavigationStack {
        SMSServicesView()
    }
    .environment(USSDCodeStore())
    .environment(AccentColorStore())
}

// MARK: - Settings / Help Screen

/// Settings tab: appearance, list display, connection warning, how USSD works, about and links.
struct SettingsView: View {
    @Environment(USSDCodeStore.self) private var store
    @Environment(AccentColorStore.self) private var accentColorStore

    @AppStorage("darkModePreference") private var darkMode: Int = 0
    @AppStorage("quickActionTileStyle") private var quickActionTileStyle: Int = 0
    @AppStorage("showNetworkStatus") private var showNetworkStatus = false
    @AppStorage("defaultTab") private var defaultTab = HomeTab.home.rawValue
    @AppStorage("quickPurchaseNoConfirmDefault") private var quickPurchaseNoConfirmDefault = false

    /// Fires at most once per launch — `defaultTab` is only meant to auto-push
    /// `.database`/`.directory` the moment Ajustes first appears on a fresh launch, not every
    /// time the user switches back to this tab after navigating elsewhere.
    @State private var hasAutoNavigatedToLaunchDestination = false
    @State private var isShowingDatabaseOnLaunch = false
    @State private var isShowingSMSServicesOnLaunch = false
    @State private var isShowingDirectoryOnLaunch = false

    /// Unlocks the hidden "Buscar en Database" row — 5 taps on the version text below within 3
    /// seconds toggles it. Not persisted-and-forgotten as a one-way unlock: toggling lets whoever
    /// found it hide the row again the same way, and staying an `@AppStorage` bool (rather than a
    /// plain `@State`) means the row stays revealed across relaunches once found.
    @AppStorage("showDatabaseSearch") private var showDatabaseSearch = false
    @State private var versionTapTimestamps: [Date] = []
    @State private var toastMessage: String?
    @State private var toastIcon = "lock.open.fill"
    @State private var toastTask: Task<Void, Never>?

    /// Backs the three "Configuraciones" SMS rows (LTE, 3G/4G check, MMS) in Cuenta — these dial
    /// straight from the row, no sub-screen, so `SettingsView` needs its own compose-SMS state
    /// same as `SMSCodeListView`'s (duplicated rather than shared, per this app's usual approach
    /// to a handful of independent action rows).
    @State private var pendingSMSInputCode: USSDCode?
    @State private var smsInputText = ""
    @State private var pendingSMS: PendingSMS?
    @State private var showsCannotSendTextAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section("Preferencias") {
                    // Inline pickers in a List don't reliably inherit `.tint()` from an ancestor
                    // (e.g. the TabView's) for their selected-value text/chevron — tint each one
                    // directly so it actually follows the user's accent color choice.
                    Picker("Tema", selection: $darkMode) {
                        Text("Por Defecto").tag(0)
                        Text("Claro").tag(1)
                        Text("Oscuro").tag(2)
                    }
                    .tint(accentColorStore.color)

                    Picker("Estilo de Acciones Rápidas", selection: $quickActionTileStyle) {
                        Text("Relleno").tag(0)
                        Text("Contorno").tag(1)
                    }
                    .tint(accentColorStore.color)

                    Toggle("Aviso de señal celular", isOn: $showNetworkStatus)

                    Picker("Pestaña Inicial", selection: $defaultTab) {
                        ForEach(HomeTab.launchOptions(includingDatabase: showDatabaseSearch)) { tab in
                            Text(tab.displayName).tag(tab.rawValue)
                        }
                    }
                    .tint(accentColorStore.color)

                    ColorPicker(
                        "Color de Acento",
                        selection: Binding(
                            get: { accentColorStore.color },
                            set: { accentColorStore.color = $0 }
                        ),
                        supportsOpacity: false
                    )

                    if accentColorStore.color.hexString != Color.brandCyan.hexString {
                        Button("Restablecer Color por Defecto") {
                            accentColorStore.resetToDefault()
                        }
                    }
                }

                Section("Utilidades") {
                    NavigationLink {
                        RemindersListView()
                    } label: {
                        Label("Recordatorios", systemImage: "bell.badge.fill")
                    }

                    NavigationLink {
                        SMSServicesView()
                    } label: {
                        Label("Servicios por SMS", systemImage: "envelope.badge")
                    }

                    NavigationLink {
                        WifiRoomsProvinceListView()
                    } label: {
                        Label("Salas y Zonas WiFi", systemImage: "wifi")
                    }

                    NavigationLink {
                        YellowPagesSearchView()
                    } label: {
                        Label("Buscar en Directorio", systemImage: "magnifyingglass")
                    }

                    if showDatabaseSearch {
                        NavigationLink {
                            DirectorySearchView()
                        } label: {
                            Label("Buscar en Database", systemImage: "cylinder.split.1x2")
                        }
                    }
                }

                Section("Cuenta") {

                    if let payPerUseCode = store.code(withId: "data-pay-per-use") {
                        Button {
                            guard !payPerUseCode.code.isEmpty else { return }
                            DialService.dial(payPerUseCode.code)
                        } label: {
                            HStack {
                                Label("Tarifa por Consumo (Datos)", systemImage: "dollarsign.circle.fill")
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                        }
                        .disabled(payPerUseCode.code.isEmpty)
                    }

                    if let configGroup = store.group(named: "Configuraciones") {
                        ForEach(configGroup.codes) { code in
                            Button {
                                selectSMS(code)
                            } label: {
                                HStack {
                                    if let icon = code.icon {
                                        Label(code.localizedTitle, systemImage: icon)
                                    } else {
                                        Text(code.localizedTitle)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                }
                            }
                        }
                    }

                    NavigationLink {
                        FriendsPlanManageView()
                    } label: {
                        Label("Gestionar Plan Amigo", systemImage: "person.2.badge.gearshape.fill")
                    }

                    NavigationLink {
                        TransferPinSettingsView()
                    } label: {
                        Label("Gestionar PIN de Transferencia", systemImage: "key.fill")
                    }
                }

                Section("Acerca de") {
                    NavigationLink {
                        CallerIDSettingsView()
                    } label: {
                        Label("Identificador de Llamadas (*99)", systemImage: "phone.badge.checkmark")
                    }

                    NavigationLink {
                        SiriShortcutsHelpView()
                    } label: {
                        Label("Siri y Atajos de Voz", systemImage: "waveform")
                    }

                    NavigationLink {
                        HelpSettingsView()
                    } label: {
                        Label("Ayuda (Manual de Uso)", systemImage: "questionmark.circle.fill")
                    }

                    Label("No está afiliada, avalada ni patrocinada por ETECSA. Los códigos pueden cambiar en cualquier momento a discreción del operador.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    VStack(spacing: 4) {
                        Text("Versión \(AppVersion) (\(AppBuild))")
                            .font(.caption)
                            .contentShape(Rectangle())
                            .onTapGesture { registerVersionTap() }

                        Link(destination: URL(string: "https://github.com/albertolicea00")!) {
                            Text("by @albertolicea00")
                                .font(.caption)
                        }
                        .tint(.secondary)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationDestination(isPresented: $isShowingDatabaseOnLaunch) { DirectorySearchView() }
            .navigationDestination(isPresented: $isShowingSMSServicesOnLaunch) { SMSServicesView() }
            .navigationDestination(isPresented: $isShowingDirectoryOnLaunch) { YellowPagesSearchView() }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // A stored `defaultTab` of "settings" predates removing the bare Ajustes option
                // from "Pestaña Inicial", or ".database" if database search is not unlocked —
                // normalize it so the Picker doesn't show a blank selection.
                if defaultTab == HomeTab.settings.rawValue || (!showDatabaseSearch && defaultTab == HomeTab.database.rawValue) {
                    defaultTab = HomeTab.home.rawValue
                }
                guard !hasAutoNavigatedToLaunchDestination else { return }
                hasAutoNavigatedToLaunchDestination = true
                if defaultTab == HomeTab.database.rawValue {
                    isShowingDatabaseOnLaunch = true
                } else if defaultTab == HomeTab.smsServices.rawValue {
                    isShowingSMSServicesOnLaunch = true
                } else if defaultTab == HomeTab.directory.rawValue {
                    isShowingDirectoryOnLaunch = true
                }
            }
            .alert(
                pendingSMSInputCode?.localizedTitle ?? "",
                isPresented: Binding(
                    get: { pendingSMSInputCode != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingSMSInputCode = nil
                            smsInputText = ""
                        }
                    }
                ),
                presenting: pendingSMSInputCode
            ) { code in
                TextField(code.inputPlaceholder ?? "Dato", text: $smsInputText)
                    .keyboardType(.phonePad)
                Button("Continuar") { composeSMS(code, input: smsInputText) }
                Button("Cancelar", role: .cancel) {}
            } message: { code in
                Text(code.localizedDetails)
            }
            .alert("No se Puede Enviar SMS", isPresented: $showsCannotSendTextAlert) {
                Button("Entendido", role: .cancel) {}
            } message: {
                Text("Este dispositivo no puede enviar mensajes de texto (por ejemplo, el Simulador de Xcode no soporta SMS).")
            }
            .sheet(item: $pendingSMS) { pending in
                MessageComposeView(recipient: pending.recipient, body: pending.body)
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                HStack(spacing: 8) {
                    Image(systemName: toastIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accentColorStore.color)
                    Text(toastMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: toastMessage)
    }

    /// 5 taps within 3 seconds on "Versión X (Y)" toggles the hidden "Buscar en Database" row —
    /// old timestamps outside the 3s window are dropped first so 5 taps spread out over a minute
    /// don't quietly accumulate into an accidental unlock.
    private func registerVersionTap() {
        let now = Date()
        versionTapTimestamps.append(now)
        versionTapTimestamps.removeAll { now.timeIntervalSince($0) > 3 }

        if versionTapTimestamps.count >= 5 {
            showDatabaseSearch.toggle()
            versionTapTimestamps.removeAll()

            let isUnlocked = showDatabaseSearch
            if !isUnlocked && defaultTab == HomeTab.database.rawValue {
                defaultTab = HomeTab.home.rawValue
            }
            showToast(
                message: isUnlocked ? "Búsqueda en Database desbloqueada" : "Búsqueda en Database oculta",
                icon: isUnlocked ? "cylinder.split.1x2" : "lock.fill"
            )
        } else {
            let feedback = UIImpactFeedbackGenerator(style: .light)
            feedback.impactOccurred()
        }
    }

    private func showToast(message: String, icon: String) {
        toastTask?.cancel()
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        toastMessage = message
        toastIcon = icon
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                toastMessage = nil
            }
        }
    }

    private func selectSMS(_ code: USSDCode) {
        if code.requiresInput {
            smsInputText = ""
            pendingSMSInputCode = code
        } else {
            composeSMS(code, input: "")
        }
    }

    private func composeSMS(_ code: USSDCode, input: String) {
        guard MFMessageComposeViewController.canSendText() else {
            showsCannotSendTextAlert = true
            return
        }
        pendingSMS = PendingSMS(recipient: code.code, body: code.resolvedSMSBody(input: input))
    }
}

/// Ajustes › Gestionar Plan Amigo — Agregar and Eliminar are two fully independent forms (each
/// with its own Número field + contact picker) since they dial different strings; duplicating the
/// form is simpler than making one shared control smart enough to handle both. Also carries the
/// Settings-only "Consultar Plan Amigo" query, distinct from Home's own `friends-plan` button.
private struct FriendsPlanManageView: View {
    @Environment(USSDCodeStore.self) private var store
    @Environment(AccentColorStore.self) private var accentColorStore

    @State private var addFriendNumber = ""
    @State private var showingAddFriendContactPicker = false
    @State private var showsAddFriendInvalidNumberWarning = false

    @State private var removeFriendNumber = ""
    @State private var showingRemoveFriendContactPicker = false
    @State private var showsRemoveFriendInvalidNumberWarning = false

    var body: some View {
        List {
            Section {
                if let activateCode = store.code(withId: "friends-plan-activate") {
                    Button {
                        dial(activateCode)
                    } label: {
                        HStack(spacing: 6) {
                            Text(activateCode.localizedTitle)
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .foregroundStyle(accentColorStore.color)
                    }
                    .disabled(activateCode.code.isEmpty)
                }

                if let deactivateCode = store.code(withId: "friends-plan-deactivate") {
                    Button {
                        dial(deactivateCode)
                    } label: {
                        HStack(spacing: 6) {
                            Text(deactivateCode.localizedTitle)
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .foregroundStyle(accentColorStore.color)
                    }
                    .disabled(deactivateCode.code.isEmpty)
                }

                if let statusCode = store.code(withId: "friends-plan-status-settings") {
                    Button {
                        dial(statusCode)
                    } label: {
                        HStack(spacing: 6) {
                            Text(statusCode.localizedTitle)
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .foregroundStyle(accentColorStore.color)
                    }
                    .disabled(statusCode.code.isEmpty)
                }
            } footer: {
                Text("Activar el Plan Amigos tiene un costo de $25.00.")
            }

            if let addCode = store.code(withId: "friends-plan-add-member") {
                Section("Agregar Amigo") {
                    HStack(spacing: 12) {
                        Button {
                            showingAddFriendContactPicker = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(.secondary)
                        }

                        TextField("Número (+53 ...)", text: $addFriendNumber)
                            .keyboardType(.numberPad)
                    }

                    Button {
                        dial(addCode, number: addFriendNumber)
                        addFriendNumber = ""
                    } label: {
                        HStack(spacing: 6) {
                            Spacer()
                            Text("Agregar")
                            Image(systemName: "arrow.right")
                        }
                    }
                    .disabled(addFriendNumber.trimmingCharacters(in: .whitespaces).isEmpty || addCode.code.isEmpty)
                }
            }

            if let removeCode = store.code(withId: "friends-plan-remove-member") {
                Section("Eliminar Amigo") {
                    HStack(spacing: 12) {
                        Button {
                            showingRemoveFriendContactPicker = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(.secondary)
                        }

                        TextField("Número (+53 ...)", text: $removeFriendNumber)
                            .keyboardType(.numberPad)
                    }

                    Button {
                        dial(removeCode, number: removeFriendNumber)
                        removeFriendNumber = ""
                    } label: {
                        HStack(spacing: 6) {
                            Spacer()
                            Text("Eliminar")
                            Image(systemName: "arrow.right")
                        }
                    }
                    .disabled(removeFriendNumber.trimmingCharacters(in: .whitespaces).isEmpty || removeCode.code.isEmpty)
                }
            }
        }
        .navigationTitle("Gestionar Plan Amigo")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddFriendContactPicker) {
            ContactPickerView { number, isValidCubanNumber in
                addFriendNumber = number
                showsAddFriendInvalidNumberWarning = !isValidCubanNumber
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingRemoveFriendContactPicker) {
            ContactPickerView { number, isValidCubanNumber in
                removeFriendNumber = number
                showsRemoveFriendInvalidNumberWarning = !isValidCubanNumber
            }
            .ignoresSafeArea()
        }
        .alert("Número no parece cubano", isPresented: $showsAddFriendInvalidNumberWarning) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("Este contacto no tiene un número con formato de móvil cubano (+53 y 8 dígitos). Revísalo antes de marcar.")
        }
        .alert("Número no parece cubano", isPresented: $showsRemoveFriendInvalidNumberWarning) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("Este contacto no tiene un número con formato de móvil cubano (+53 y 8 dígitos). Revísalo antes de marcar.")
        }
    }

    private func dial(_ code: USSDCode) {
        guard !code.code.isEmpty else { return }
        DialService.dial(code.code)
    }

    private func dial(_ code: USSDCode, number: String) {
        guard !code.code.isEmpty else { return }
        DialService.dial(code.resolvedCode(input: number))
    }
}

/// Ajustes › Gestionar PIN de Transferencia — Cambiar Clave and Guardar Clave, each its own form
/// with room to breathe (moved out of the old inline-expanding Ajustes rows into this dedicated
/// screen).
private struct TransferPinSettingsView: View {
    @Environment(USSDCodeStore.self) private var store

    @State private var currentPin = ""
    @State private var newPin = ""

    @State private var savedPin = ""
    @State private var isSavedPinPersisted = false

    var body: some View {
        List {
            Section("Cambiar Clave") {
                HStack(spacing: 12) {
                    TextField("Clave actual", text: $currentPin)
                        .textContentType(.password)
                        .keyboardType(.numberPad)
                    Divider()
                    TextField("Clave nueva", text: $newPin)
                        .textContentType(.newPassword)
                        .keyboardType(.numberPad)
                }

                if showsSamePinError {
                    Text("La clave nueva es igual a la actual.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    changePin()
                } label: {
                    HStack(spacing: 6) {
                        Spacer()
                        Text("Cambiar Clave")
                        Image(systemName: "arrow.right")
                    }
                }
                .disabled(isChangePinDisabled)
            }

            Section {
                PinRevealField(title: "Clave", text: $savedPin, isMasked: true)

                Button {
                    TransferPinStore.save(savedPin)
                    isSavedPinPersisted = true
                } label: {
                    HStack(spacing: 6) {
                        Spacer()
                        Text("Guardar Clave")
                        Image(systemName: "arrow.right")
                    }
                }
                .disabled(savedPin.trimmingCharacters(in: .whitespaces).isEmpty)

                if isSavedPinPersisted {
                    Button("Olvidar Clave Guardada", role: .destructive) {
                        TransferPinStore.delete()
                        savedPin = ""
                        isSavedPinPersisted = false
                    }
                }
            } header: {
                Text("Guardar Clave")
            } footer: {
                Text("Se guarda cifrada en el Llavero de este dispositivo (nunca sale de él) y se rellena sola en el campo Clave al transferir, tanto en Home como dentro de un contacto.")
            }
        }
        .navigationTitle("PIN de Transferencia")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let stored = TransferPinStore.load() {
                savedPin = stored
                isSavedPinPersisted = true
            }
        }
    }

    /// Blocks empty fields and a "new" PIN identical to the current one — changing to the same
    /// PIN isn't a change.
    private var isChangePinDisabled: Bool {
        currentPin.trimmingCharacters(in: .whitespaces).isEmpty
            || newPin.trimmingCharacters(in: .whitespaces).isEmpty
            || newPin == currentPin
    }

    /// Only flagged once both fields are filled in — an empty field is caught by
    /// `isChangePinDisabled` alone and doesn't need an explicit error.
    private var showsSamePinError: Bool {
        !currentPin.isEmpty && !newPin.isEmpty && newPin == currentPin
    }

    /// Dials `transfer-pin-change` (`*234*2*{current}*{new}#`), saves the new PIN to
    /// `TransferPinStore` so it stays in sync with what Transferir prefills, and clears the
    /// fields.
    private func changePin() {
        guard let code = store.code(withId: "transfer-pin-change") else { return }
        let resolved = code.resolvedCode(with: ["current": currentPin, "new": newPin])
        DialService.dial(resolved)
        TransferPinStore.save(newPin)
        savedPin = newPin
        isSavedPinPersisted = true
        currentPin = ""
        newPin = ""
    }
}

/// Ajustes › Buscar en Database — reverse number/name lookup over whichever directory database
/// file the user has copied into this app's Documents folder: Finder file sharing, the "Importar
/// Base de Datos" picker, or the "Descargar Base de Datos" button (fetches `DirectoryDatabase
/// .downloadURL`, wherever that's currently hosted). Its schema shape (v1/v2) is auto-detected from the file's
/// own tables — see `DirectoryDatabase`.
struct DirectorySearchView: View {
    @Environment(AccentColorStore.self) private var accentColorStore

    @State private var databaseFile: DirectoryDatabaseFile?
    @State private var hasSearchedForDatabase = false
    @State private var showingImporter = false
    @State private var isImporting = false
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var importErrorMessage: String?

    @State private var numberQuery = ""
    @State private var nameQuery = ""
    @State private var results: [DirectoryEntry] = []
    @State private var isSearching = false

    /// Mirrors `DirectoryDatabase`'s own minimums so the empty-state message doesn't flash "sin
    /// resultados" while the user is still short of the threshold that would actually search.
    private var hasSearchableInput: Bool {
        numberQuery.trimmingCharacters(in: .whitespaces).count >= DirectoryDatabase.minimumNumberQueryLength
            || nameQuery.trimmingCharacters(in: .whitespaces).count >= DirectoryDatabase.minimumNameQueryLength
    }

    var body: some View {
        Group {
            if !hasSearchedForDatabase {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if databaseFile == nil {
                VStack(spacing: 20) {
                    // Never names v1/v2 here — whoever copies the file in may not know which
                    // shape it is either; the app detects that on its own from its tables.
                    ContentUnavailableView(
                        "Sin Base de Datos",
                        systemImage: "externaldrive.badge.questionmark",
                        description: Text("Impórtala si ya la tienes en este dispositivo.")
                    )

                    if isDownloading {
                        VStack(spacing: 10) {
                            ProgressView(value: downloadProgress)
                                .frame(maxWidth: 200)
                            Text("Descargando… \(Int((downloadProgress * 100).rounded()))%")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("Puede tardar varios minutos, no cierres la app.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)
                    } else if isImporting {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Importando… puede tardar varios minutos, no cierres la app.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)
                    } else {
                        // One integrated card (two stacked rows, divider between) instead of two
                        // separate pill buttons — reads as one grouped action, matching the
                        // inset-grouped list rows used everywhere else in Ajustes.
                        VStack(spacing: 0) {
                            // Disabled for security and legal compliance: downloading an external phone directory
                            // database directly in-app may violate privacy laws, data protection regulations, or App
                            // Store guidelines regarding unauthorized personal data distribution. Users must supply
                            // their own file manually.
                            /*
                            DirectoryActionRow(
                                title: "Descargar Base de Datos",
                                systemImage: "arrow.down.circle.fill",
                                isEnabled: true,
                                tint: accentColorStore.color
                            ) {
                                downloadDatabase()
                            }

                            Divider().padding(.leading, 52)
                            */

                            DirectoryActionRow(
                                title: "Importar Base de Datos",
                                systemImage: "square.and.arrow.down.on.square",
                                isEnabled: true,
                                tint: accentColorStore.color
                            ) {
                                showingImporter = true
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item]) { result in
                    importDatabase(from: result)
                }
                .alert(
                    "No se Pudo Importar",
                    isPresented: Binding(
                        get: { importErrorMessage != nil },
                        set: { if !$0 { importErrorMessage = nil } }
                    )
                ) {
                    Button("Entendido", role: .cancel) {}
                } message: {
                    Text(importErrorMessage ?? "")
                }
            } else if !hasSearchableInput {
                // Idle state — the real, native search field lives at the top via `.searchable`
                // below; this is just the big centered "nothing typed yet" placeholder, same
                // pattern as Music/App Store's search tab.
                ContentUnavailableView {
                    Label("Buscar en Database", systemImage: "cylinder.split.1x2.fill")
                } description: {
                    Text("Escribe un número para buscar")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                ContentUnavailableView.search(text: numberQuery)
            } else {
                List {
                    ForEach(results) { entry in
                        DirectoryEntryRowView(entry: entry)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Buscar en Database")
        .navigationBarTitleDisplayMode(.inline)
        // Name search stays disabled for privacy and security — see README. `nameQuery` stays ""
        // forever; the rest of the code (DirectoryDatabase.search, hasSearchableInput) already
        // supports it again just by adding its own `.searchable` back (SwiftUI only supports one
        // native search field per view).
        .searchable(text: $numberQuery, prompt: "Número")
        .keyboardType(.phonePad)
        .onAppear {
            guard !hasSearchedForDatabase else { return }
            databaseFile = DirectoryDatabase.discoverDatabase()
            hasSearchedForDatabase = true
        }
        .task(id: "\(numberQuery)|\(nameQuery)") {
            guard let file = databaseFile, hasSearchableInput else {
                isSearching = false
                results = []
                return
            }
            isSearching = true
            // Debounce: wait out a pause in typing before paying for a scan over a
            // multi-million-row table, and bail if a newer keystroke already superseded us.
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }

            let searchNumber = numberQuery
            let searchName = nameQuery
            let found = await Task.detached(priority: .userInitiated) {
                DirectoryDatabase.search(numberQuery: searchNumber, nameQuery: searchName, in: file)
            }.value

            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }

    /// Copies a file the user picked (Files app, iCloud Drive, "On My iPhone", …) into this app's
    /// Documents folder, then re-runs discovery — `DirectoryDatabase` doesn't care about the
    /// filename, only what tables the copy actually has, so an unrecognized file just leaves
    /// `databaseFile` nil instead of throwing here.
    /// These dumps are 400+MB — copying on the calling thread would block the UI for however
    /// long that takes (and risk the app being killed or force-quit mid-copy, leaving a truncated
    /// file `sqlite3` can't read). So the actual `copyItem` runs on a detached background task,
    /// and its result is checked against the source's byte size before trusting it — a size
    /// mismatch means an interrupted copy, not a bad file, so it's reported as that distinctly.
    private func importDatabase(from result: Result<URL, Error>) {
        guard case let .success(sourceURL) = result else { return }
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            importErrorMessage = "No se pudo acceder a los archivos de la app."
            return
        }
        let destinationURL = documents.appendingPathComponent(sourceURL.lastPathComponent)

        isImporting = true
        Task.detached(priority: .userInitiated) {
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

            do {
                let sourceSize = try FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int

                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

                let destinationSize = try FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int
                if let sourceSize, let destinationSize, sourceSize != destinationSize {
                    try? FileManager.default.removeItem(at: destinationURL)
                    await MainActor.run {
                        isImporting = false
                        importErrorMessage = "La copia no terminó (\(destinationSize) de \(sourceSize) bytes) — inténtalo de nuevo."
                    }
                    return
                }

                let discovered = DirectoryDatabase.discoverDatabase()
                // Temporary diagnostic: surface the real sqlite error/table names instead of a
                // generic message, since a copy that opens fine on a Mac has failed here before
                // for a reason `discoverDatabase()` alone doesn't report.
                let diagnosis = discovered == nil ? DirectoryDatabase.diagnose(at: destinationURL) : nil
                await MainActor.run {
                    databaseFile = discovered
                    isImporting = false
                    if discovered == nil {
                        importErrorMessage = "El archivo se copió pero no tiene el formato esperado de base de datos.\n\nDiagnóstico: \(diagnosis ?? "?")"
                    }
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importErrorMessage = "No se pudo copiar el archivo: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Downloads `DirectoryDatabase.downloadURL` straight into Documents, then re-runs discovery —
    /// same size/shape validation as `importDatabase`, since a network transfer can be interrupted
    /// mid-download just like a Files-app copy can. Uses `URLSessionDownloadDelegate` (via
    /// `TransferProgressDelegate`, shared with the speed-test screen) so the progress bar tracks
    /// real bytes received instead of sitting at 0% until the whole 400+MB file lands.
    private func downloadDatabase() {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            importErrorMessage = "No se pudo acceder a los archivos de la app."
            return
        }
        let destinationURL = documents.appendingPathComponent(DirectoryDatabase.downloadURL.lastPathComponent)

        isDownloading = true
        downloadProgress = 0
        Task.detached(priority: .userInitiated) {
            let delegate = TransferProgressDelegate { bytesWritten, bytesExpected in
                guard bytesExpected > 0 else { return }
                Task { @MainActor in
                    downloadProgress = Double(bytesWritten) / Double(bytesExpected)
                }
            }

            do {
                var request = URLRequest(url: DirectoryDatabase.downloadURL)
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                let (tempURL, response) = try await URLSession.shared.download(for: request, delegate: delegate)

                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    try? FileManager.default.removeItem(at: tempURL)
                    let status = (response as? HTTPURLResponse)?.statusCode
                    await MainActor.run {
                        isDownloading = false
                        importErrorMessage = "No se pudo descargar la base de datos"
                            + (status.map { " (HTTP \($0))" } ?? "") + "."
                    }
                    return
                }

                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)

                let discovered = DirectoryDatabase.discoverDatabase()
                let diagnosis = discovered == nil ? DirectoryDatabase.diagnose(at: destinationURL) : nil
                await MainActor.run {
                    databaseFile = discovered
                    isDownloading = false
                    if discovered == nil {
                        importErrorMessage = "El archivo se descargó pero no tiene el formato esperado de base de datos.\n\nDiagnóstico: \(diagnosis ?? "?")"
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: destinationURL)
                await MainActor.run {
                    isDownloading = false
                    importErrorMessage = "No se pudo descargar el archivo: \(error.localizedDescription)"
                }
            }
        }
    }
}

/// Ajustes › Buscar en Directorio — placeholder search screen for a live/online reverse
/// number-and-name directory lookup (formerly "Páginas Amarillas"). Not wired to a real source
/// yet — the form exists so the fields it will use are fixed, but "Buscar" stays disabled until
/// there's an actual endpoint to call. Distinct from "Buscar en Database" (`DirectorySearchView`),
/// which searches a file the user has copied onto the device themselves.
struct YellowPagesSearchView: View {
    // Fields this will use once wired up (see GitHub issue #3) — kept here so the planned shape
    // is fixed, but not rendered while this stays a placeholder. `nombre` and `calle` stay
    // commented since they're too identifying/specific to expose as search criteria.
    // @State private var nombre = ""
    // @State private var categoria = ""
    // @State private var telefono = ""
    // @State private var calle = ""
    // @State private var municipio = ""
    // @State private var provincia = ""

    var body: some View {
        ContentUnavailableView(
            "En Construcción",
            systemImage: "hammer.fill",
            description: Text("Buscar en Directorio todavía no está disponible.")
        )
        .navigationTitle("Buscar en Directorio")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One row of the "Sin Base de Datos" action card — icon, title, and a chevron, styled like a
/// native grouped-list row (not a standalone button) so "Descargar"/"Importar" read as one
/// integrated component instead of two separate pills.
private struct DirectoryActionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let isEnabled: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(isEnabled ? tint : .secondary)
                Spacer()
                if isEnabled {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// Ajustes › Preferencias — appearance and general behavior toggles.
/// Ajustes › Ayuda — how USSD works, in plain language.
private struct HelpSettingsView: View {
    var body: some View {
        Form {
            Section("Qué es Qvacell") {
                SettingsInfoRow(
                    title: "¿Qué hace la app?",
                    text: "Qvacell da acceso rápido a los códigos USSD de servicio de ETECSA (Cubacel): saldo, compras, transferencias y otras utilidades, todo desde una app sin conexión y sin dependencias."
                )
                Link(destination: URL(string: "https://github.com/albertolicea00/Qvacell-ios")!) {
                    Label("Código fuente en GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            Section("Idioma") {
                SettingsInfoRow(
                    title: "¿Cómo cambio el idioma?",
                    text: "Qvacell no tiene un selector de idioma propio — sigue el idioma que elijas para la app en Ajustes de iOS. Si tu iPhone está en inglés, la app se muestra en inglés; si está en español (u otro idioma sin traducir), se muestra en español."
                )
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Label("Cambiar Idioma en Ajustes de iOS", systemImage: "globe")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                    }
                }
            }

            Section("Cómo Funciona el USSD") {
                SettingsInfoRow(
                    title: "¿Qué es el USSD?",
                    text: "El USSD es un protocolo telefónico que te permite interactuar con tu operadora marcando códigos especiales como *222#. Necesita señal celular, no datos ni Wi-Fi. Toca cualquier código de la lista y el marcador del sistema se abre listo para enviarlo — el propio iOS te pide confirmar antes de que la llamada se realice."
                )
                SettingsInfoRow(
                    title: "Códigos que piden un dato",
                    text: "Algunos códigos, como recargar con tarjeta, necesitan un número adicional (p. ej. *662*{tarjeta}#). Al tocarlos, primero se pide ese dato y luego se marca el código completo."
                )
                Link(destination: URL(string: "https://github.com/albertolicea00/Qvacell-ios/blob/main/Qvacell/codes.json")!) {
                    Label("Descargar Todos los Códigos", systemImage: "arrow.down.doc")
                }
            }

            Section("Compras: Acción sin Confirmación") {
                SettingsInfoRow(
                    title: "¿Qué hace?",
                    text: "En la pestaña Compras hay un interruptor \"Acción sin Confirmación\". Actívalo y los códigos que lo soportan marcan directo el paso de confirmación de ETECSA, ahorrándote un paso — solo actívalo si ya confías en lo que vas a comprar."
                )
            }

            Section("Recordatorios") {
                SettingsInfoRow(
                    title: "¿Qué hace?",
                    text: "En Ajustes › Utilidades › Recordatorios puedes crear notificaciones locales (sin servidor, sin internet) para que te avisen cuando toca comprar un paquete, recargar saldo o hacer una transferencia. Hay una sección por plantilla, y puedes agregar tantos recordatorios de cada una como necesites — uno por cada línea que manejes."
                )
                SettingsInfoRow(
                    title: "Ejecutar desde el recordatorio",
                    text: "Comprar Paquete te lleva directo a la pestaña Compras (no tiene un solo código fijo, es todo un catálogo). Recargar Saldo te pide el número de la tarjeta justo antes de marcar (nunca se guarda). Transferencia recuerda el número de destino y te pide el monto, con tu Clave de Transferencia ya rellenada si la tienes guardada."
                )
                SettingsInfoRow(
                    title: "Recurrencia y notificación",
                    text: "Elige avisarte una sola vez, todos los días, cada semana, cada mes o cada ciertos días. Desde la notificación misma puedes \"Marcar como hecho\" o \"Posponer 1 día\" sin abrir la app; tocarla abre el detalle del recordatorio. También puedes crear un recordatorio totalmente personalizado, sin plantilla. Todos empiezan sin ningún recordatorio activo — los creas tú, a tu medida."
                )
            }

            Section("Plan Amigo") {
                SettingsInfoRow(
                    title: "Gestionar Plan Amigo",
                    text: "En Ajustes › Cuenta › Gestionar Plan Amigo puedes activarlo, desactivarlo, agregar o eliminar un amigo (con su número o eligiéndolo de Contactos), y consultar su estado. Activar el Plan Amigos tiene un costo de $25.00."
                )
            }

            Section("PIN de Transferencia") {
                SettingsInfoRow(
                    title: "Cambiar y guardar tu PIN",
                    text: "En Ajustes › Cuenta › Gestionar PIN de Transferencia puedes cambiar el PIN que usas para transferir saldo, o guardarlo en este dispositivo para que se rellene solo cada vez que transfieras (desde Home o desde un contacto). Se guarda cifrado en este iPhone y nunca sale de él."
                )
            }

            Section("Servicios por SMS") {
                SettingsInfoRow(
                    title: "¿Qué es esto?",
                    text: "Son servicios de ETECSA que se usan enviando un SMS, no marcando un código — tarifas, DHL y vuelos, deportes, noticias, frases y horóscopos. Algunos son suscripciones (se marcan con la etiqueta \"Suscripción\") y pueden tener un costo recurrente. Necesitas un dispositivo que pueda enviar SMS (el Simulador de Xcode, por ejemplo, no puede)."
                )
            }

            Section("Salas y Zonas WiFi") {
                SettingsInfoRow(
                    title: "¿Qué muestra?",
                    text: "Para cada provincia cubana, lista las salas de navegación pagas de ETECSA (con su cantidad de puestos) y las zonas de WIFI público gratis, agrupadas por municipio. Es información pública de ETECSA, incluida en la app — no necesita conexión para verse."
                )
                Link(destination: URL(string: "https://github.com/albertolicea00/Qvacell-ios/blob/main/Qvacell/wifi_navigation_rooms.json")!) {
                    Label("Descargar JSON de Salas y Zonas WiFi", systemImage: "arrow.down.doc")
                }
            }

            // Section("Medir Velocidad de Internet") {
            //     SettingsInfoRow(
            //         title: "¿Cómo funciona?",
            //         text: "Mide ping, velocidad de descarga y de subida de tu conexión actual (datos móviles o WiFi). La prueba consume los datos que uses durante ella — ten cuidado si tienes un plan de datos limitado."
            //     )
            // }

            Section("Buscar en Directorio") {
                SettingsInfoRow(
                    title: "¿Qué es?",
                    text: "En Ajustes › Utilidades › Buscar en Directorio puedes buscar números y contactos comerciales en el directorio telefónico de ETECSA (función actualmente en desarrollo)."
                )
            }

            Section("Buscar en Database") {
                SettingsInfoRow(
                    title: "¿De dónde salen los datos?",
                    text: "La app no incluye ninguna base de datos ni la descarga automáticamente — tienes que traer tú mismo el archivo SQLite (.db) de base de datos (con el botón «Importar» o copiándolo mediante Finder) para poder buscar."
                )
                SettingsInfoRow(
                    title: "Búsqueda solo por número",
                    text: "Por privacidad, la búsqueda inversa en la base de datos se realiza únicamente a partir de números de teléfono, no por nombre."
                )
            }

        }
        .navigationTitle("Ayuda")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Caller ID Settings & Instructions Screen

/// Ajustes › Identificador de Llamadas (*99) — instructions, live CallKit extension status,
/// and deep link to iOS Phone Settings.
private struct CallerIDSettingsView: View {
    @Environment(AccentColorStore.self) private var accentColorStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: CXCallDirectoryManager.EnabledStatus = .unknown
    @State private var isChecking = true

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "phone.badge.checkmark")
                        .font(.system(size: 46))
                        .foregroundStyle(accentColorStore.color)
                        .padding(.top, 6)

                    Text("Identificador de Llamadas (*99)")
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Text("Identifica automáticamente quién te llama con cobro revertido (*99) mostrando el nombre real de tu contacto en la pantalla de llamada.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Estado de la Extensión") {
                HStack(spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.title3)
                        .foregroundStyle(statusColor)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(statusSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isChecking {
                        ProgressView()
                    }
                }
                .padding(.vertical, 4)
            }

            Section("¿Qué es y cómo funciona?") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("En Cuba, cuando alguien te llama a cobro revertido marcando **\\*99**, ETECSA envía el número entrante envuelto con 14 dígitos (por ejemplo, **99535XXXXXXX99**).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Por eso, la app Teléfono de tu iPhone normalmente no sabe quién es y solo muestra esa serie de números. La extensión de Qvacell le enseña a iOS a reconocerlo y mostrar el nombre real del contacto guardado en tu agenda.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Pasos para Activar en tu iPhone") {
                StepRowView(stepNumber: "1", text: "Abre los **Ajustes** de tu iPhone.", icon: "gear")
                StepRowView(stepNumber: "2", text: "Toca en **Teléfono**.", icon: "phone.fill")
                StepRowView(stepNumber: "3", text: "Entra en **Bloqueo e identificación de llamadas**.", icon: "shield.checkered")
                StepRowView(stepNumber: "4", text: "Activa el interruptor de **Qvacell** (CallerID).", icon: "checkmark.circle.fill")
            }

            Section("Importante") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Debes abrir la pestaña Contactos en Qvacell al menos una vez para que la app sincronice tu lista de contactos con la extensión.", systemImage: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label("Solo se identifican contactos que ya tengas guardados en tu agenda con número celular cubano (+53 5XXXXXXX).", systemImage: "person.crop.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label("Tus contactos se procesan 100% en el dispositivo (offline), sin servidores ni internet.", systemImage: "lock.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Text("Actívala manualmente en Ajustes › Teléfono › Bloqueo e Identificación de Llamadas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Por políticas de seguridad de Apple, ninguna aplicación puede activar esta extensión por sí misma, ni abrir esa pantalla de Ajustes directamente; debe autorizarse manualmente desde los ajustes de iOS.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Identificador *99")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { checkStatus() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                checkStatus()
            }
        }
    }

    private var statusTitle: String {
        switch status {
        case .enabled: return "Extensión Activada"
        case .disabled: return "Extensión Desactivada"
        default: return "Estado No Disponible"
        }
    }

    private var statusSubtitle: String {
        switch status {
        case .enabled: return "Las llamadas por cobrar (*99) mostrarán el nombre de tu contacto."
        case .disabled: return "Actívala en Ajustes › Teléfono para que funcione."
        default: return "Solo verificable en un iPhone físico real."
        }
    }

    private var statusIcon: String {
        switch status {
        case .enabled: return "checkmark.circle.fill"
        case .disabled: return "exclamationmark.triangle.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .enabled: return .green
        case .disabled: return .orange
        default: return .secondary
        }
    }

    private func checkStatus() {
        isChecking = true
        CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(withIdentifier: CallerIDStore.extensionBundleID) { newStatus, _ in
            DispatchQueue.main.async {
                self.status = newStatus
                self.isChecking = false
            }
        }
    }

}

private struct StepRowView: View {
    let stepNumber: String
    let text: LocalizedStringKey
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 26, height: 26)
                Text(stepNumber)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
            }
            Text(text)
                .font(.subheadline)
            Spacer()
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Siri & Shortcuts Instructions Screen

/// Ajustes › Siri y Atajos de Voz — voice command instructions and deep links to Siri settings.
private struct SiriShortcutsHelpView: View {
    @Environment(AccentColorStore.self) private var accentColorStore

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 46))
                        .foregroundStyle(accentColorStore.color)
                        .padding(.top, 6)

                    Text("Siri y Atajos de Voz")
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Text("Controla Qvacell usando tu voz con Siri o integrando acciones en la app Atajos de iOS.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("¿Cómo funciona?") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No necesitas configurar nada: al instalar la app, Siri y Atajos reconocen automáticamente «Qvacell».", systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Label("Cada orden por voz abre la app y prepara el marcado exacto, solicitando confirmación del sistema antes de llamar.", systemImage: "shield.checkered")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Llamar Oculto o por Cobrar (*99)") {
                SiriPhraseRow(phrase: "Oye Siri, llama con 99 a [Contacto] en Qvacell", subtitle: "Llamada a cobro revertido (*99) a un contacto")
                SiriPhraseRow(phrase: "Oye Siri, llama pagando el a [Contacto] en Qvacell", subtitle: "Frase alternativa para cobro revertido")
                SiriPhraseRow(phrase: "Oye Siri, llama con *99 en Qvacell", subtitle: "Abre el marcador con el prefijo *99")
                SiriPhraseRow(phrase: "Oye Siri, llama con oculto a [Contacto] en Qvacell", subtitle: "Llama ocultando tu número con #31#")
                SiriPhraseRow(phrase: "Oye Siri, llama con privado en Qvacell", subtitle: "Abre el marcador con el prefijo #31#")
            }

            Section("Consultar Saldo y Servicios") {
                SiriPhraseRow(phrase: "Oye Siri, consulta mi saldo en Qvacell", subtitle: "Consulta de saldo principal (*222#)")
                SiriPhraseRow(phrase: "Oye Siri, marca Bonos y Planes en Qvacell", subtitle: "Consulta de datos, bonos y voz (*222*266#)")
            }

            Section {
                SiriPhraseRow(phrase: "Oye Siri, compra Plan de 4.5GB en Qvacell", subtitle: "Plan de datos móviles 4.5GB (LTE)")
                SiriPhraseRow(phrase: "Oye Siri, compra Combo 2GB en Qvacell", subtitle: "Plan combinado de datos, voz y SMS")
                SiriPhraseRow(phrase: "Oye Siri, compra Plan de 20 SMS en Qvacell", subtitle: "Paquete de mensajes de texto")
            } header: {
                Text("Comprar Planes por Voz")
            } footer: {
                Text("Usa siempre el código estándar seguro que abre la pantalla de confirmación interactiva de ETECSA antes de realizar la compra.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("App Atajos de iOS") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Puedes integrar cualquiera de estas acciones dentro de la app **Atajos** de iOS para crear rutinas personalizadas, widgets en tu pantalla de inicio o ejecutarlas desde tu Apple Watch.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Button {
                    openSettings()
                } label: {
                    HStack {
                        Spacer()
                        Label("Abrir Ajustes de Siri para Qvacell", systemImage: "gear")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .tint(accentColorStore.color)
            } footer: {
                Text("En los ajustes de iOS puedes verificar que los permisos de «Aprender de esta app» y «Sugerencias» estén activados para Qvacell.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Siri y Atajos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

private struct SiriPhraseRow: View {
    @Environment(AccentColorStore.self) private var accentColorStore
    let phrase: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.caption)
                    .foregroundStyle(accentColorStore.color)
                    .padding(.top, 2)
                Text(phrase)
                    .font(.subheadline.weight(.semibold))
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
        }
        .padding(.vertical, 3)
    }
}

/// One title + body row inside a Settings section.
private struct SettingsInfoRow: View {
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    @Environment(AccentColorStore.self) private var accentColorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accentColorStore.color)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SettingsView()
        .environment(USSDCodeStore())
        .environment(AccentColorStore())
        .environment(WifiRoomsStore())
}

// MARK: - Wifi Navigation Rooms & Hotspots

/// Ajustes › Salas y Zonas WiFi — every Cuban province from ETECSA's own public "Navigation
/// rooms and public spaces (WIFI)" directory (`wifi_navigation_rooms.json`, scraped once from
/// https://www.etecsa.cu/en/rooms-public-spaces — see README for the exact source URLs). Picking
/// a province shows its navigation rooms (seat counts) and free WIFI hotspots by municipality.
struct WifiRoomsProvinceListView: View {
    @Environment(WifiRoomsStore.self) private var store

    var body: some View {
        List {
            ForEach(store.provinces) { province in
                NavigationLink {
                    WifiRoomsDetailView(province: province)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(province.province)
                            .font(.body.weight(.medium))
                        Text("\(province.rooms.count) ") + Text("salas de navegación") + Text(" · \(province.hotspots.reduce(0) { $0 + $1.spots.count }) ") + Text("zonas wifi")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Salas y Zonas WiFi")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        WifiRoomsProvinceListView()
    }
    .environment(WifiRoomsStore())
}

/// One province's navigation rooms (paid, with seat counts) and free WIFI hotspots, grouped by
/// municipality and collapsed behind a `DisclosureGroup` since a big province can list 100+ spots.
struct WifiRoomsDetailView: View {
    let province: WifiProvince

    @Environment(AccentColorStore.self) private var accentColorStore
    @State private var searchText = ""

    private var filteredRooms: [WifiRoom] {
        guard !searchText.isEmpty else { return province.rooms }
        return province.rooms.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.address.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Municipality name match keeps the whole group; otherwise only its matching spots survive
    /// — a group with none is dropped entirely so an unmatched municipality doesn't leave an
    /// empty, pointless `DisclosureGroup` behind.
    private var filteredHotspotGroups: [WifiHotspotGroup] {
        guard !searchText.isEmpty else { return province.hotspots }
        return province.hotspots.compactMap { group in
            if group.municipality.localizedCaseInsensitiveContains(searchText) {
                return group
            }
            let matches = group.spots.filter { $0.localizedCaseInsensitiveContains(searchText) }
            guard !matches.isEmpty else { return nil }
            return WifiHotspotGroup(municipality: group.municipality, spots: matches)
        }
    }

    var body: some View {
        List {
            if !filteredRooms.isEmpty {
                Section("Salas de Navegación") {
                    ForEach(filteredRooms) { room in
                        HStack(alignment: .center, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                if let positions = room.positions {
                                    (Text("\(positions) ") + Text("puestos"))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Text(room.name)
                                    .font(.body.weight(.medium))
                                if !room.address.isEmpty {
                                    Text(room.address)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button {
                                MapsService.openSearch(for: mapsQuery(name: room.name, address: room.address))
                            } label: {
                                Image(systemName: "map")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(accentColorStore.color)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !filteredHotspotGroups.isEmpty {
                Section("Zonas WiFi Públicas") {
                    ForEach(filteredHotspotGroups) { group in
                        DisclosureGroup {
                            ForEach(group.spots, id: \.self) { spot in
                                HStack {
                                    Text(spot)
                                        .font(.subheadline)
                                    Spacer()
                                    Button {
                                        MapsService.openSearch(for: mapsQuery(name: spot, address: group.municipality))
                                    } label: {
                                        Image(systemName: "map")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(accentColorStore.color)
                                }
                            }
                        } label: {
                            HStack {
                                Text(group.municipality)
                                Spacer()
                                Text("\(group.spots.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(province.province)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar sala o zona wifi")
    }

    /// "Name, address, Province, Cuba" (address falls back to just the province when ETECSA's
    /// listing didn't include a street address) — enough context for Maps to geocode a Cuban
    /// place it has no exact pin for.
    private func mapsQuery(name: String, address: String) -> String {
        let locality = address.isEmpty ? province.province : address
        return "\(name), \(locality), \(province.province), Cuba"
    }
}

#Preview {
    NavigationStack {
        WifiRoomsDetailView(province: WifiProvince(
            province: "Artemisa",
            rooms: [
                WifiRoom(name: "Multiservice Center Artemisa", address: "Calle 50 e/ 27 y 29", positions: 4),
                WifiRoom(name: "Youth Club Bauta III", address: "", positions: nil),
            ],
            hotspots: [
                WifiHotspotGroup(municipality: "Artemisa", spots: ["Park Las Cañas", "Boulevard"]),
            ]
        ))
    }
    .environment(AccentColorStore())
}

// MARK: - Reminders List

struct RemindersListView: View {
    @Environment(ReminderManager.self) private var reminderManager
    @Environment(AccentColorStore.self) private var accentColorStore

    @State private var templateForNewReminder: ReminderTemplate?
    @State private var reminderToEdit: Reminder?
    @State private var reminderToDelete: Reminder?
    @State private var showingDeleteAlert = false

    var body: some View {
        List {
            // One section per template — each can hold any number of reminders (several phone
            // lines to recargar/transferir, not just a single on/off switch).
            ForEach(ReminderTemplate.quickTemplates) { template in
                Section {
                    let instances = reminderManager.reminders(forTemplate: template.id)
                    if instances.isEmpty {
                        Text("Sin recordatorios de este tipo todavía.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(instances) { reminder in
                            ReminderRow(reminder: reminder)
                                .contentShape(Rectangle())
                                .onTapGesture { reminderToEdit = reminder }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        reminderToDelete = reminder
                                        showingDeleteAlert = true
                                    } label: {
                                        Label("Eliminar", systemImage: "trash")
                                    }
                                }
                        }
                    }

                    Button {
                        templateForNewReminder = template
                    } label: {
                        Label {
                            Text("Agregar ") + Text(template.localizedTitle)
                        } icon: {
                            Image(systemName: "plus.circle")
                        }
                    }
                } header: {
                    Label(template.localizedTitle, systemImage: template.iconName)
                }
            }

            Section("Personalizados") {
                if reminderManager.customReminders.isEmpty {
                    Text("Sin recordatorios personalizados.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(reminderManager.customReminders) { reminder in
                        ReminderRow(reminder: reminder)
                            .contentShape(Rectangle())
                            .onTapGesture { reminderToEdit = reminder }
                            .swipeActions {
                                Button(role: .destructive) {
                                    reminderToDelete = reminder
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            }
                    }
                }

                Button {
                    templateForNewReminder = .custom
                } label: {
                    Label("Nuevo Recordatorio Personalizado", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("Recordatorios")
        .sheet(item: $templateForNewReminder) { template in
            AddReminderView(template: template)
        }
        .sheet(item: $reminderToEdit) { reminder in
            AddReminderView(
                template: ReminderTemplate.quickTemplates.first { $0.id == reminder.templateKey } ?? .custom,
                reminderToEdit: reminder
            )
        }
        .alert("¿Eliminar recordatorio?", isPresented: $showingDeleteAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                if let reminder = reminderToDelete { reminderManager.delete(reminder) }
            }
        } message: {
            Text("Esta acción no se puede deshacer.")
        }
    }
}

struct ReminderRow: View {
    let reminder: Reminder
    @Environment(ReminderManager.self) private var reminderManager
    @Environment(AccentColorStore.self) private var accentColorStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.iconName)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(accentColorStore.color, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title).font(.headline)
                Text(reminder.recurrence.localizedLabel) + Text(" · \(DateFormatter.localizedString(from: reminder.date, dateStyle: .medium, timeStyle: .short))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { reminder.isEnabled },
                set: { reminderManager.setEnabled($0, for: reminder) }
            ))
            .labelsHidden()
            .tint(accentColorStore.color)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add/Edit Reminder

struct AddReminderView: View {
    @Environment(\.dismiss) private var dismiss
    let template: ReminderTemplate
    var reminderToEdit: Reminder? = nil

    @Environment(ReminderManager.self) private var reminderManager

    @State private var title: String = ""
    @State private var message: String = ""
    @State private var date: Date = Date().addingTimeInterval(3600)
    @State private var recurrence: ReminderRecurrenceKind = .none
    @State private var customIntervalDays: Int = 30
    @State private var phoneNumber: String = ""
    /// True once the user has typed into the title field themselves — until then, typing a phone
    /// number auto-fills "Hacer Transferencia — 51234567" so several reminders from the same
    /// template (several lines to recargar/transferir) stay distinguishable at a glance.
    @State private var isTitleCustomized = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Recordatorio") {
                    TextField("Título", text: Binding(
                        get: { title },
                        set: { title = $0; isTitleCustomized = true }
                    ))
                    TextField("Mensaje", text: $message)
                }

                if template.needsPhoneNumber {
                    Section(
                        header: Text("Número de Teléfono"),
                        footer: Text("Se usará como destino al ejecutar la transferencia.")
                    ) {
                        TextField("Ej: 51234567", text: $phoneNumber)
                            .keyboardType(.numberPad)
                            .onChange(of: phoneNumber) { _, newValue in
                                guard !isTitleCustomized, reminderToEdit == nil else { return }
                                title = newValue.isEmpty ? template.title : "\(template.title) — \(newValue)"
                            }
                    }
                }

                Section("Cuándo") {
                    DatePicker("Fecha y hora", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Picker("Repetir", selection: $recurrence) {
                        ForEach(ReminderRecurrenceKind.allCases) { kind in
                            Text(kind.localizedLabel).tag(kind)
                        }
                    }
                    if recurrence == .custom {
                        Stepper("Cada \(customIntervalDays) días", value: $customIntervalDays, in: 2...365)
                    }
                }
            }
            .navigationTitle(reminderToEdit == nil ? template.localizedTitle : "Editar Recordatorio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { populate() }
        }
    }

    private func populate() {
        if let edit = reminderToEdit {
            title = edit.title
            message = edit.message
            date = edit.date
            recurrence = edit.recurrence
            customIntervalDays = edit.customIntervalDays
            phoneNumber = edit.phoneNumber
        } else {
            title = template.title
            message = template.message
            recurrence = template.defaultRecurrence
        }
    }

    private func save() {
        let reminder = Reminder(
            id: reminderToEdit?.id ?? UUID(),
            title: title,
            message: message,
            iconName: template.iconName,
            ussdCodeId: template.ussdCodeId,
            phoneNumber: phoneNumber,
            date: date,
            recurrence: recurrence,
            customIntervalDays: customIntervalDays,
            isEnabled: true,
            templateKey: template.id == ReminderTemplate.custom.id ? nil : template.id
        )

        reminderManager.requestAuthorizationIfNeeded()
        if reminderToEdit != nil {
            reminderManager.update(reminder)
        } else {
            reminderManager.add(reminder)
        }
        dismiss()
    }
}

// MARK: - Reminder Detail (opened from the list or from a notification tap)

struct ReminderDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let reminder: Reminder
    @Environment(ReminderManager.self) private var reminderManager
    @Environment(AccentColorStore.self) private var accentColorStore
    @Environment(TabRouter.self) private var tabRouter

    @State private var showingDeleteAlert = false
    @State private var showingExecuteSheet = false

    private var template: ReminderTemplate? {
        ReminderTemplate.quickTemplates.first { $0.id == reminder.templateKey }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: reminder.iconName)
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                            .frame(width: 80, height: 80)
                            .background(accentColorStore.color, in: Circle())
                        Text(reminder.title).font(.title2).fontWeight(.bold)
                        if !reminder.message.isEmpty {
                            Text(reminder.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top)

                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Repetición") { Text(reminder.recurrence.localizedLabel) }
                        LabeledContent("Próxima Vez", value: DateFormatter.localizedString(from: reminder.date, dateStyle: .medium, timeStyle: .short))
                        if !reminder.phoneNumber.isEmpty {
                            LabeledContent("Número", value: reminder.phoneNumber)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    if let template, template.action != .none {
                        Button {
                            switch template.action {
                            case .openPurchases:
                                tabRouter.pendingTab = .purchase
                                dismiss()
                            case .dialSingleInput, .dialTransfer:
                                showingExecuteSheet = true
                            case .none:
                                break
                            }
                        } label: {
                            Label("Ejecutar", systemImage: "phone.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(accentColorStore.color, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                    }

                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("Eliminar Recordatorio", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .navigationTitle("Recordatorio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .alert("¿Eliminar recordatorio?", isPresented: $showingDeleteAlert) {
                Button("Cancelar", role: .cancel) {}
                Button("Eliminar", role: .destructive) {
                    reminderManager.delete(reminder)
                    dismiss()
                }
            } message: {
                Text("Esta acción no se puede deshacer.")
            }
            .sheet(isPresented: $showingExecuteSheet) {
                if let template {
                    ExecuteReminderSheet(reminder: reminder, template: template, onDialed: { dismiss() })
                }
            }
        }
    }
}

/// The "just before dialing" prompt for a reminder whose action needs one more piece of data
/// that can't be known ahead of time: a scratch-card number (`.dialSingleInput`) or a transfer
/// amount (`.dialTransfer`, phone/PIN prefilled from the reminder and `TransferPinStore`).
private struct ExecuteReminderSheet: View {
    let reminder: Reminder
    let template: ReminderTemplate
    let onDialed: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(USSDCodeStore.self) private var store

    @State private var cardNumber = ""
    @State private var phoneNumber = ""
    @State private var pin = ""
    @State private var amount = ""

    private var canDial: Bool {
        switch template.action {
        case .dialSingleInput:
            return !cardNumber.trimmingCharacters(in: .whitespaces).isEmpty
        case .dialTransfer:
            return !phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty
                && !pin.trimmingCharacters(in: .whitespaces).isEmpty
                && !amount.trimmingCharacters(in: .whitespaces).isEmpty
        case .none, .openPurchases:
            return false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch template.action {
                case .dialSingleInput:
                    Section(footer: Text("El número de la tarjeta de recarga, tal como aparece raspada.")) {
                        TextField("Número de Tarjeta", text: $cardNumber)
                            .keyboardType(.numberPad)
                    }
                case .dialTransfer:
                    Section {
                        TextField("Número de Teléfono", text: $phoneNumber)
                            .keyboardType(.numberPad)
                        TextField("Clave de Transferencia", text: $pin)
                            .keyboardType(.numberPad)
                        TextField("Monto", text: $amount)
                            .keyboardType(.decimalPad)
                    }
                case .none, .openPurchases:
                    EmptyView()
                }
            }
            .navigationTitle("Confirmar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Marcar") { dial() }
                        .disabled(!canDial)
                }
            }
            .onAppear {
                phoneNumber = reminder.phoneNumber
                pin = TransferPinStore.load() ?? ""
            }
        }
    }

    private func dial() {
        guard let codeId = reminder.ussdCodeId, let code = store.code(withId: codeId) else { return }

        let resolved: String
        switch template.action {
        case .dialSingleInput:
            resolved = code.resolvedCode(input: cardNumber)
        case .dialTransfer:
            resolved = code.resolvedCode(with: ["phoneNumber": phoneNumber, "pin": pin, "amount": amount])
        case .none, .openPurchases:
            return
        }

        DialService.dial(resolved)
        dismiss()
        onDialed()
    }
}
