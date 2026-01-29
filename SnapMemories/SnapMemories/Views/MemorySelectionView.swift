import SwiftUI

struct MemorySelectionView: View {
    @ObservedObject var viewModel: ImportViewModel
    @ObservedObject var purchaseService: PurchaseService
    let onShowPaywall: () -> Void
    
    @State private var searchText = ""
    
    private var filteredMemories: [Memory] {
        if searchText.isEmpty {
            return viewModel.memories
        }
        return viewModel.memories.filter { $0.displayDate.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var duplicateDetector = DuplicateDetector.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header stats
            headerView
            
            // Memory list
            List {
                ForEach(filteredMemories) { memory in
                    MemoryRow(
                        memory: memory,
                        isSelected: viewModel.selectedIds.contains(memory.id),
                        isDuplicate: duplicateDetector.isDuplicate(memory),
                        onToggle: { viewModel.toggleSelection(memory) }
                    )
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search by date")
            
            // Bottom action bar
            actionBar
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.totalCount) Memories")
                        .font(.headline)
                    
                    if !viewModel.dateRange.isEmpty {
                        Text(viewModel.dateRange)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if viewModel.duplicateCount > 0 {
                    Label("\(viewModel.duplicateCount) duplicates", systemImage: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            // Free limit warning
            if !purchaseService.hasUnlimitedAccess {
                HStack {
                    Image(systemName: "info.circle")
                    Text("\(purchaseService.remainingFreeDownloads) free downloads remaining")
                    Spacer()
                    Button("Unlock All") {
                        onShowPaywall()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.yellow)
                }
                .font(.caption)
                .padding(10)
                .background(.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Action Bar
    
    private var actionBar: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(viewModel.selectedCount) selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Selection buttons
                Button("All") { viewModel.selectAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                
                Button("None") { viewModel.deselectAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            
            // Download button
            Button {
                if !purchaseService.canDownload(additionalCount: viewModel.selectedCount) {
                    onShowPaywall()
                } else {
                    Task {
                        await viewModel.downloadSelected(purchaseService: purchaseService)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Download \(viewModel.selectedCount) Memories")
                }
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(viewModel.selectedCount > 0 ? Color.yellow : Color.gray.opacity(0.3))
                .cornerRadius(12)
            }
            .disabled(viewModel.selectedCount == 0)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Memory Row

struct MemoryRow: View {
    let memory: Memory
    let isSelected: Bool
    let isDuplicate: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Selection checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .yellow : .secondary)
                
                // Media type icon
                ZStack {
                    Circle()
                        .fill(memory.isVideo ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: memory.isVideo ? "video.fill" : "photo.fill")
                        .foregroundStyle(memory.isVideo ? .blue : .green)
                }
                
                // Details
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.displayDate)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 8) {
                        Text(memory.mediaType)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if memory.coordinates != nil {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        if isDuplicate {
                            Text("Already saved")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                
                Spacer()
                
                if isDuplicate {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isDuplicate ? 0.6 : 1)
    }
}

#Preview {
    MemorySelectionView(
        viewModel: ImportViewModel(),
        purchaseService: PurchaseService.shared,
        onShowPaywall: {}
    )
}
