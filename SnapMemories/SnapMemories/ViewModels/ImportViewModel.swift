import Foundation
import SwiftUI

@MainActor
class ImportViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var state: ImportState = .idle
    @Published var memories: [Memory] = []
    @Published var selectedIds: Set<UUID> = []
    @Published var errors: [String] = []
    
    // Progress tracking
    @Published var downloadProgress: Double = 0
    @Published var currentDownloadName: String = ""
    @Published var successCount: Int = 0
    @Published var failedCount: Int = 0
    @Published var skippedCount: Int = 0
    
    // Services
    private let zipService = ZipService.shared
    private let downloadService = DownloadService.shared
    private let photosService = PhotosService.shared
    private let duplicateDetector = DuplicateDetector.shared
    
    private var extractedFolder: URL?
    
    // MARK: - Computed Properties
    
    var selectedMemories: [Memory] {
        memories.filter { selectedIds.contains($0.id) }
    }
    
    var selectedCount: Int {
        selectedIds.count
    }
    
    var totalCount: Int {
        memories.count
    }
    
    var duplicateCount: Int {
        memories.filter { duplicateDetector.isDuplicate($0) }.count
    }
    
    var dateRange: String {
        guard !memories.isEmpty else { return "" }
        
        let sortedDates = memories.compactMap { $0.parsedDate }.sorted()
        guard let first = sortedDates.first, let last = sortedDates.last else { return "" }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return formatter.string(from: first)
        } else {
            return "\(formatter.string(from: first)) - \(formatter.string(from: last))"
        }
    }
    
    // MARK: - Import ZIP
    
    func importZip(from url: URL) async {
        state = .extractingZip
        errors.removeAll()
        
        do {
            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                throw ZipError.extractionFailed("Cannot access file")
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Copy to temp location for extraction
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(at: url, to: tempURL)
            
            // Extract ZIP
            extractedFolder = try await zipService.extractZip(from: tempURL)
            
            // Clean up temp ZIP copy
            try? FileManager.default.removeItem(at: tempURL)
            
            // Parse JSON
            state = .parsingJSON
            guard let folder = extractedFolder else {
                throw ZipError.extractionFailed("Extraction folder not found")
            }
            
            let jsonURL = try zipService.findMemoriesJSON(in: folder)
            memories = try zipService.parseMemoriesJSON(at: jsonURL)

            // Check if download URLs have expired (uses network probe as fallback)
            let expired = await downloadService.checkUrlExpirationAsync(memories)
            if expired {
                state = .error("Your Snapchat download links have expired. Please request a new data export from Snapchat and try again.")
                cleanup()
                return
            }

            // Pre-select all non-duplicate memories
            selectedIds = Set(memories.filter { !duplicateDetector.isDuplicate($0) }.map { $0.id })

            state = .ready
            
        } catch {
            state = .error(error.localizedDescription)
            cleanup()
        }
    }
    
    // MARK: - Selection
    
    func toggleSelection(_ memory: Memory) {
        if selectedIds.contains(memory.id) {
            selectedIds.remove(memory.id)
        } else {
            selectedIds.insert(memory.id)
        }
    }
    
    func selectAll() {
        selectedIds = Set(memories.map { $0.id })
    }
    
    func deselectAll() {
        selectedIds.removeAll()
    }
    
    func selectNonDuplicates() {
        selectedIds = Set(memories.filter { !duplicateDetector.isDuplicate($0) }.map { $0.id })
    }
    
    // MARK: - Download
    
    /// Tracks where to resume from after paywall purchase
    private var pendingDownloads: [Memory] = []
    private var pendingResumeIndex: Int = 0

    func downloadSelected(purchaseService: PurchaseService) async {
        let toDownload = selectedMemories
        guard !toDownload.isEmpty else { return }

        // Request photos permission
        do {
            try await photosService.requestAuthorization()
        } catch {
            state = .error(error.localizedDescription)
            return
        }

        // Reset counters
        successCount = 0
        failedCount = 0
        skippedCount = 0
        downloadProgress = 0
        errors.removeAll()
        pendingDownloads = toDownload
        pendingResumeIndex = 0

        await performDownload(from: 0, memories: toDownload, purchaseService: purchaseService)
    }

    /// Resume downloading after the user unlocks via paywall
    func resumeDownload(purchaseService: PurchaseService) async {
        guard !pendingDownloads.isEmpty else { return }
        await performDownload(from: pendingResumeIndex, memories: pendingDownloads, purchaseService: purchaseService)
    }

    private func performDownload(from startIndex: Int, memories: [Memory], purchaseService: PurchaseService) async {
        let total = memories.count
        state = .downloading(progress: Double(startIndex) / Double(total), current: "Starting...")

        for index in startIndex..<total {
            let memory = memories[index]

            // Update progress
            let progress = Double(index) / Double(total)
            currentDownloadName = memory.displayDate
            state = .downloading(progress: progress, current: memory.displayDate)

            // Skip duplicates
            if duplicateDetector.isDuplicate(memory) {
                skippedCount += 1
                continue
            }

            // Check if user has hit the free limit
            if !purchaseService.canDownload() {
                let remaining = total - index
                pendingResumeIndex = index
                state = .paywallRequired(downloaded: successCount, remaining: remaining)
                return
            }

            do {
                // Download media
                let (data, fileExtension) = try await downloadService.downloadMemory(memory)

                // Save to Photos
                if memory.isVideo {
                    let tempURL = try downloadService.saveToTemporaryFile(data: data, extension: fileExtension)
                    defer { downloadService.cleanupTemporaryFile(tempURL) }

                    try await photosService.saveVideo(
                        fileURL: tempURL,
                        creationDate: memory.parsedDate,
                        location: memory.clLocation
                    )
                } else {
                    try await photosService.savePhoto(
                        data: data,
                        creationDate: memory.parsedDate,
                        location: memory.clLocation,
                        fileExtension: fileExtension
                    )
                }

                // Mark as downloaded
                duplicateDetector.markAsDownloaded(memory)
                purchaseService.recordDownload()
                successCount += 1

            } catch {
                failedCount += 1
                errors.append("\(memory.displayDate): \(error.localizedDescription)")
            }
        }

        // Complete
        pendingDownloads = []
        pendingResumeIndex = 0
        state = .complete(successful: successCount, failed: failedCount, skipped: skippedCount)
        cleanup()
    }
    
    // MARK: - Reset
    
    func reset() {
        cleanup()
        state = .idle
        memories.removeAll()
        selectedIds.removeAll()
        errors.removeAll()
        downloadProgress = 0
        currentDownloadName = ""
        successCount = 0
        failedCount = 0
        skippedCount = 0
    }
    
    private func cleanup() {
        if let folder = extractedFolder {
            zipService.cleanup(folder: folder)
            extractedFolder = nil
        }
    }
}
