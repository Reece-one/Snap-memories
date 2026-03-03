import SwiftUI
import StoreKit
import RevenueCat

@main
struct SnapMemoriesApp: App {
    @StateObject private var purchaseService = PurchaseService.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

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
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(purchaseService)
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .onChange(of: hasCompletedOnboarding) { completed in
                        if completed {
                            // Request app review after a short delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if let scene = UIApplication.shared.connectedScenes
                                    .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                                    SKStoreReviewController.requestReview(in: scene)
                                }
                            }
                        }
                    }
            }
        }
    }
}
