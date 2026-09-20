import SwiftUI

@main
struct QvacellApp: App {
    @State private var store = USSDCodeStore()
    @State private var accentColorStore = AccentColorStore()
    @State private var wifiRoomsStore = WifiRoomsStore()
    @State private var reminderManager = ReminderManager.shared
    @State private var tabRouter = TabRouter()
    @AppStorage("darkModePreference") private var darkModePreference: Int = 0

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(accentColorStore)
                .environment(wifiRoomsStore)
                .environment(reminderManager)
                .environment(tabRouter)
                .tint(accentColorStore.color)
                .preferredColorScheme(darkModePreference == 1 ? .light : (darkModePreference == 2 ? .dark : nil))
        }
    }
}
