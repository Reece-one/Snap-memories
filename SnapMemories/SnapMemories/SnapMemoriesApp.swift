import SwiftUI
import StoreKit
import RevenueCat

@main
struct SnapMemoriesApp: App {
    @StateObject private var purchaseService = PurchaseService.shared

    init() {
        Purchases.logLevel = .debug

        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let secrets = NSDictionary(contentsOfFile: path),
              let apiKey = secrets["RevenueCatAPIKey"] as? String else {
            fatalError("Missing Secrets.plist or RevenueCatAPIKey. See Secrets.example.plist.")
        }

        Purchases.configure(withAPIKey: apiKey)

        // Debug: test if StoreKit can see the product directly
        Task {
            do {
                let products = try await Product.products(for: ["com.nettlelite.snapkeeper.unlimited"])
                print("🛍️ StoreKit found products: \(products.map { $0.id })")
            } catch {
                print("🛍️ StoreKit error: \(error)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(purchaseService)
        }
    }
}
