import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                // MARK: - Page 1: Export Your Data
                VStack(spacing: 24) {
                    Text("Export Your Data")
                        .font(.title.weight(.bold))

                    Image("Onboard1")
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        StepRow(number: 1, text: "Go to **accounts.snapchat.com**")
                        StepRow(number: 2, text: "Tap **My Data** in the sidebar")
                        StepRow(number: 3, text: "Tick **Export JSON Files**")
                        StepRow(number: 4, text: "Choose a timeframe & tap **Submit**")
                        StepRow(number: 5, text: "Wait for Snapchat to prepare your data")
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    Button {
                        withAnimation {
                            currentPage = 1
                        }
                    } label: {
                        Text("Next")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.yellow)
                            .cornerRadius(25)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
                }
                .tag(0)

                // MARK: - Page 2: Upload to Snap Keeper
                VStack(spacing: 24) {
                    Text("Upload to Snap Keeper")
                        .font(.title.weight(.bold))

                    Image("Onboard2")
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        StepRow(number: 1, text: "Once ready, **download the ZIP** file")
                        StepRow(number: 2, text: "Upload the ZIP directly to the app")
                        StepRow(number: 3, text: "**Do not unzip** the file — we handle that!")
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    Button {
                        hasCompletedOnboarding = true
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.yellow)
                            .cornerRadius(25)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
                }
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }
}

// MARK: - Step Row

private struct StepRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundColor(.black)
                .frame(width: 24, height: 24)
                .background(Color.yellow)
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
