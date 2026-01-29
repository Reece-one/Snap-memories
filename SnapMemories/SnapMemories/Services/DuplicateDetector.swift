import Foundation

/// Detects and tracks downloaded memories to avoid duplicates
class DuplicateDetector {
    static let shared = DuplicateDetector()
    
    private let userDefaultsKey = "SnapMemories_DownloadedHashes"
    private var downloadedHashes: Set<String>
    
    private init() {
        // Load previously downloaded hashes from UserDefaults
        if let saved = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] {
            self.downloadedHashes = Set(saved)
        } else {
            self.downloadedHashes = []
        }
    }
    
    /// Generate a unique hash for a memory based on date + URL
    func generateHash(for memory: Memory) -> String {
        // Use date + download URL as unique identifier
        let combined = "\(memory.date)|\(memory.mediaDownloadUrl)"
        
        // Create a simple hash
        var hash = 0
        for char in combined.unicodeScalars {
            hash = 31 &* hash &+ Int(char.value)
        }
        
        return String(format: "%08x", abs(hash))
    }
    
    /// Check if a memory has already been downloaded
    func isDuplicate(_ memory: Memory) -> Bool {
        let hash = generateHash(for: memory)
        return downloadedHashes.contains(hash)
    }
    
    /// Mark a memory as downloaded
    func markAsDownloaded(_ memory: Memory) {
        let hash = generateHash(for: memory)
        downloadedHashes.insert(hash)
        saveToUserDefaults()
    }
    
    /// Mark multiple memories as downloaded
    func markAsDownloaded(_ memories: [Memory]) {
        for memory in memories {
            let hash = generateHash(for: memory)
            downloadedHashes.insert(hash)
        }
        saveToUserDefaults()
    }
    
    /// Get count of previously downloaded items
    var downloadedCount: Int {
        downloadedHashes.count
    }
    
    /// Filter out duplicates from a list of memories
    func filterDuplicates(from memories: [Memory]) -> (unique: [Memory], duplicates: [Memory]) {
        var unique: [Memory] = []
        var duplicates: [Memory] = []
        
        for memory in memories {
            if isDuplicate(memory) {
                duplicates.append(memory)
            } else {
                unique.append(memory)
            }
        }
        
        return (unique, duplicates)
    }
    
    /// Clear all download history (for testing/reset)
    func clearHistory() {
        downloadedHashes.removeAll()
        saveToUserDefaults()
    }
    
    // MARK: - Private
    
    private func saveToUserDefaults() {
        UserDefaults.standard.set(Array(downloadedHashes), forKey: userDefaultsKey)
    }
}
