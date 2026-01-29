import SwiftUI
import RevenueCat

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchaseService: PurchaseService
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: [.yellow.opacity(0.3), .orange.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Header
                        VStack(spacing: 16) {
                            Image(systemName: "infinity")
                                .font(.system(size: 60, weight: .bold))
                                .foregroundStyle(.yellow)
                            
                            Text("Unlimited Downloads")
                                .font(.largeTitle.weight(.bold))
                            
                            Text("You've reached the free limit of \(PurchaseService.FREE_LIMIT) downloads")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                        
                        // Features
                        VStack(alignment: .leading, spacing: 16) {
                            FeatureRow(icon: "infinity", text: "Unlimited memory downloads")
                            FeatureRow(icon: "bolt.fill", text: "Download all at once")
                            FeatureRow(icon: "clock.arrow.circlepath", text: "Import new exports anytime")
                            FeatureRow(icon: "heart.fill", text: "Support indie development")
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .padding(.horizontal)
                        
                        // Price and purchase button
                        if let offering = purchaseService.currentOffering,
                           let package = offering.lifetime ?? offering.availablePackages.first {
                            VStack(spacing: 12) {
                                Text("One-time purchase")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Button {
                                    Task {
                                        await purchase(package: package)
                                    }
                                } label: {
                                    HStack {
                                        if isLoading {
                                            ProgressView()
                                                .tint(.black)
                                        } else {
                                            Text("Unlock for \(package.priceString)")
                                        }
                                    }
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background(Color.yellow)
                                    .cornerRadius(14)
                                }
                                .disabled(isLoading)
                                .padding(.horizontal)
                            }
                        } else {
                            ProgressView("Loading...")
                                .onAppear {
                                    Task {
                                        await purchaseService.fetchOfferings()
                                    }
                                }
                        }
                        
                        // Error message
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                        
                        // Restore purchases
                        Button {
                            Task {
                                await restore()
                            }
                        } label: {
                            Text("Restore Purchases")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .disabled(isLoading)
                        
                        // Terms
                        VStack(spacing: 4) {
                            Text("Payment will be charged to your Apple ID account")
                            Link("Terms of Service", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                            Link("Privacy Policy", destination: URL(string: "https://www.apple.com/privacy/")!)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: purchaseService.hasUnlimitedAccess) { newValue in
            if newValue {
                dismiss()
            }
        }
    }
    
    private func purchase(package: Package) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await purchaseService.purchase(package: package)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func restore() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await purchaseService.restorePurchases()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.yellow)
                .frame(width: 30)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
}

#Preview {
    PaywallView()
        .environmentObject(PurchaseService.shared)
}
