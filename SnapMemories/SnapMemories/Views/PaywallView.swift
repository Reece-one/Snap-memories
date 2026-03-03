import SwiftUI
import RevenueCat

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var purchaseService: PurchaseService

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var appeared = false
    @State private var ctaPulse = false

    var body: some View {
        ZStack {
            // Clean background
            (colorScheme == .dark ? Color(hex: "0F172A") : Color.white)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button row
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                // Hero area — top 30-35%
                Image("PaywallImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 200)
                    .padding(.horizontal, 20)

                Spacer().frame(height: 24)

                // Headline — 28-32pt, Bold, benefit-focused, loss-aversion
                Text("Never Lose a Memory Again")
                    .font(.system(size: 28, weight: .bold))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(colorScheme == .dark ? Color(hex: "F9FAFB") : Color(hex: "1F2937"))
                    .padding(.horizontal, 20)

                Spacer().frame(height: 24)

                // 3 benefit bullets — outcome-first, loss-aversion framing
                VStack(alignment: .leading, spacing: 16) {
                    BenefitBullet(text: "Never hit your download limit again")
                    BenefitBullet(text: "Save every memory before they expire")
                    BenefitBullet(text: "One payment — no monthly bills, ever")
                }
                .padding(.horizontal, 32)

                Spacer().frame(height: 24)

                Spacer()

                // Price + CTA section — always above fold
                if let offering = purchaseService.currentOffering,
                   let package = offering.lifetime ?? offering.availablePackages.first {
                    VStack(spacing: 12) {
                        // Price display — large, prominent
                        Text(package.priceString)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(colorScheme == .dark ? Color(hex: "F9FAFB") : Color(hex: "1F2937"))

                        Text("One payment. Yours forever.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "6B7280"))

                        Spacer().frame(height: 8)

                        // CTA Button — full-width, high contrast, 56-72px tall
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
                                    Text("Unlock Lifetime Access")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(Color(hex: "EAB308"))
                            .cornerRadius(14)
                        }
                        .disabled(isLoading)
                        .scaleEffect(ctaPulse ? 1.02 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: ctaPulse)
                        .padding(.horizontal, 20)

                        // Error message
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }

                        // Restore purchases — secondary, low visual weight
                        Button {
                            Task {
                                await restore()
                            }
                        } label: {
                            Text("Restore Purchase")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "6B7280"))
                        }
                        .disabled(isLoading)

                        // Fine print / legal
                        VStack(spacing: 4) {
                            Link("Terms of Service", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                            Link("Privacy Policy", destination: URL(string: "https://nettlelite.com/snapkeeper/privacy")!)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "6B7280").opacity(0.7))

                        Text("Not affiliated with or endorsed by Snap Inc.")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: "6B7280").opacity(0.5))
                    }
                    .padding(.bottom, 24)
                } else {
                    ProgressView("Loading...")
                        .padding(.bottom, 40)
                        .onAppear {
                            Task {
                                await purchaseService.fetchOfferings()
                            }
                        }
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                appeared = true
            }
            ctaPulse = true
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

struct BenefitBullet: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color(hex: "EAB308"))

            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(colorScheme == .dark ? Color(hex: "F9FAFB") : Color(hex: "1F2937"))
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    PaywallView()
        .environmentObject(PurchaseService.shared)
}
