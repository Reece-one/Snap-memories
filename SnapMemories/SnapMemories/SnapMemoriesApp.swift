import SwiftUI
import RevenueCat

@main
struct SnapMemoriesApp: App {
    @StateObject private var purchaseService = PurchaseService.shared
    
    init() {
        // Configure RevenueCat - Replace with your API key
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: "YOUR_REVENUECAT_API_KEY")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(purchaseService)
        }
    }
}
