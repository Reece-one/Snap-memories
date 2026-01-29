import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = ImportViewModel()
    @EnvironmentObject private var purchaseService: PurchaseService
    
    @State private var showFileImporter = false
    @State private var showPaywall = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.yellow.opacity(0.1), Color.orange.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Main content based on state
                contentView
            }
            .navigationTitle("SnapMemories")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if case .ready = viewModel.state {
                        Menu {
                            Button("Select All") { viewModel.selectAll() }
                            Button("Deselect All") { viewModel.deselectAll() }
                            Button("Select Non-Duplicates") { viewModel.selectNonDuplicates() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await viewModel.importZip(from: url)
                    }
                }
            case .failure(let error):
                viewModel.state = .error(error.localizedDescription)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch viewModel.state {
        case .idle:
            IdleView(onSelectFile: { showFileImporter = true })
            
        case .selectingFile:
            Color.clear
            
        case .extractingZip:
            LoadingView(title: "Extracting ZIP...", subtitle: "Please wait")
            
        case .parsingJSON:
            LoadingView(title: "Reading Memories...", subtitle: "Parsing data")
            
        case .ready:
            MemorySelectionView(
                viewModel: viewModel,
                purchaseService: purchaseService,
                onShowPaywall: { showPaywall = true }
            )
            
        case .downloading(let progress, let current):
            DownloadProgressView(
                progress: progress,
                currentItem: current,
                successCount: viewModel.successCount,
                failedCount: viewModel.failedCount,
                skippedCount: viewModel.skippedCount,
                totalCount: viewModel.selectedCount
            )
            
        case .complete(let successful, let failed, let skipped):
            CompleteView(
                successful: successful,
                failed: failed,
                skipped: skipped,
                errors: viewModel.errors,
                onReset: { viewModel.reset() }
            )
            
        case .error(let message):
            ErrorView(message: message, onRetry: { viewModel.reset() })
        }
    }
}

// MARK: - Idle View

struct IdleView: View {
    let onSelectFile: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            // Ghost icon
            Image(systemName: "square.and.arrow.down.fill")
                .font(.system(size: 80))
                .foregroundStyle(.yellow)
                .padding()
                .background(
                    Circle()
                        .fill(.yellow.opacity(0.2))
                        .frame(width: 160, height: 160)
                )
            
            VStack(spacing: 12) {
                Text("Import Snapchat Memories")
                    .font(.title2.weight(.semibold))
                
                Text("Select your Snapchat data export ZIP file")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: onSelectFile) {
                Label("Select ZIP File", systemImage: "folder")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .cornerRadius(25)
            }
            
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("How to get your data:")
                    .font(.footnote.weight(.medium))
                
                Text("1. Go to Snapchat Settings → My Data")
                Text("2. Request your data export")
                Text("3. Download the ZIP file from the email")
                Text("4. Import it here")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - Loading View

struct LoadingView: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.red)
            
            Text("Something went wrong")
                .font(.title2.weight(.semibold))
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundColor(.black)
        }
        .padding()
    }
}

// MARK: - Complete View

struct CompleteView: View {
    let successful: Int
    let failed: Int
    let skipped: Int
    let errors: [String]
    let onReset: () -> Void
    
    @State private var showErrors = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Success icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                
                Text("Download Complete!")
                    .font(.title.weight(.bold))
                
                // Stats
                VStack(spacing: 12) {
                    StatRow(icon: "checkmark.circle", color: .green, label: "Saved", value: "\(successful)")
                    
                    if skipped > 0 {
                        StatRow(icon: "arrow.uturn.right.circle", color: .orange, label: "Skipped (Duplicates)", value: "\(skipped)")
                    }
                    
                    if failed > 0 {
                        StatRow(icon: "xmark.circle", color: .red, label: "Failed", value: "\(failed)")
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                
                if !errors.isEmpty {
                    Button {
                        showErrors.toggle()
                    } label: {
                        Label(showErrors ? "Hide Errors" : "Show Errors", systemImage: "exclamationmark.triangle")
                    }
                    .foregroundColor(.red)
                    
                    if showErrors {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(errors, id: \.self) { error in
                                Text("• \(error)")
                                    .font(.caption)
                            }
                        }
                        .padding()
                        .background(.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                Text("Open Photos app to see your memories!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Button(action: onReset) {
                    Text("Import More")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(Color.yellow)
                        .cornerRadius(25)
                }
            }
            .padding()
        }
    }
}

struct StatRow: View {
    let icon: String
    let color: Color
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 30)
            
            Text(label)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PurchaseService.shared)
}
