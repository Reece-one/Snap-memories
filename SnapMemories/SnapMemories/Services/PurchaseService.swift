import Foundation
import RevenueCat

/// Manages in-app purchases via RevenueCat
class PurchaseService: ObservableObject {
    static let shared = PurchaseService()
    
    /// Free tier limit - 100 downloads before paywall
    static let FREE_LIMIT = 100
    
    /// RevenueCat entitlement identifier
    private let unlimitedEntitlementID = "unlimited_downloads"
    
    /// RevenueCat offering identifier
    private let offeringID = "default"
    
    // MARK: - Published Properties
    
    @Published private(set) var hasUnlimitedAccess: Bool = false
    @Published private(set) var currentOffering: Offering?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    
    // Track downloads in current session + persisted
    @Published private(set) var totalDownloadsUsed: Int = 0
    
    private let downloadsKey = "SnapMemories_TotalDownloads"
    
    private init() {
        // Load persisted download count
        totalDownloadsUsed = UserDefaults.standard.integer(forKey: downloadsKey)
        
        // Check for cached customer info
        Task {
            await checkSubscription()
        }
    }
    
    // MARK: - Public Methods
    
    /// Check current subscription status
    func checkSubscription() async {
        await MainActor.run { isLoading = true }
        
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            await updateAccessStatus(from: customerInfo)
        } catch {
            await MainActor.run {
                errorMessage = "Failed to check subscription: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run { isLoading = false }
    }
    
    /// Fetch available offerings (products)
    func fetchOfferings() async {
        await MainActor.run { isLoading = true }
        
        do {
            let offerings = try await Purchases.shared.offerings()
            await MainActor.run {
                self.currentOffering = offerings.current
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to fetch products: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run { isLoading = false }
    }
    
    /// Purchase unlimited access (one-time purchase)
    func purchase(package: Package) async throws {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let result = try await Purchases.shared.purchase(package: package)
            await updateAccessStatus(from: result.customerInfo)
        } catch {
            await MainActor.run {
                if let purchaseError = error as? RevenueCat.ErrorCode {
                    if purchaseError == .purchaseCancelledError {
                        // User cancelled - not an error
                        return
                    }
                }
                errorMessage = "Purchase failed: \(error.localizedDescription)"
            }
            throw error
        }
        
        await MainActor.run { isLoading = false }
    }
    
    /// Restore previous purchases
    func restorePurchases() async throws {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            await updateAccessStatus(from: customerInfo)
            
            if !hasUnlimitedAccess {
                await MainActor.run {
                    errorMessage = "No previous purchases found"
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Restore failed: \(error.localizedDescription)"
            }
            throw error
        }
        
        await MainActor.run { isLoading = false }
    }
    
    /// Check if user can download more files
    func canDownload(additionalCount: Int = 1) -> Bool {
        if hasUnlimitedAccess {
            return true
        }
        return (totalDownloadsUsed + additionalCount) <= Self.FREE_LIMIT
    }
    
    /// Get remaining free downloads
    var remainingFreeDownloads: Int {
        if hasUnlimitedAccess {
            return Int.max
        }
        return max(0, Self.FREE_LIMIT - totalDownloadsUsed)
    }
    
    /// Increment download count
    func recordDownload(count: Int = 1) {
        totalDownloadsUsed += count
        UserDefaults.standard.set(totalDownloadsUsed, forKey: downloadsKey)
    }
    
    /// Check if paywall should be shown
    var shouldShowPaywall: Bool {
        !hasUnlimitedAccess && totalDownloadsUsed >= Self.FREE_LIMIT
    }
    
    // MARK: - Private Methods
    
    private func updateAccessStatus(from customerInfo: CustomerInfo) async {
        await MainActor.run {
            // Check if user has the unlimited entitlement
            hasUnlimitedAccess = customerInfo.entitlements[unlimitedEntitlementID]?.isActive == true
        }
    }
}

// MARK: - Package Extension for Display

extension Package {
    var priceString: String {
        return storeProduct.localizedPriceString
    }
    
    var productName: String {
        return storeProduct.localizedTitle
    }
    
    var productDescription: String {
        return storeProduct.localizedDescription
    }
}
