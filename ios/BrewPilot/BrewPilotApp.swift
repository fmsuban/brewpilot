import SwiftUI

@main
struct BrewPilotApp: App {
    @StateObject private var session = BrewSession()
    @State private var tab = BrewPilotApp.initialTab()

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                ConnectView()
                    .tabItem { Label("Connect", systemImage: "antenna.radiowaves.left.and.right") }
                    .tag(0)
                RecipeView()
                    .tabItem { Label("Recipe", systemImage: "list.bullet.clipboard") }
                    .tag(1)
                BrewView()
                    .tabItem { Label("Brew", systemImage: "timer") }
                    .tag(2)
                ReportView()
                    .tabItem { Label("Report", systemImage: "chart.xyaxis.line") }
                    .tag(3)
            }
            .environmentObject(session)
            .preferredColorScheme(.dark)
            .tint(.caramel)
        }
    }

    /// Screenshot helper: `-initialTab N` launch argument wins, else the
    /// `initialTab` default (0 when unset).
    static func initialTab() -> Int {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-initialTab"), i + 1 < args.count {
            return min(max(Int(args[i + 1]) ?? 0, 0), 3)
        }
        return min(max(UserDefaults.standard.integer(forKey: "initialTab"), 0), 3)
    }
}
