import Foundation
import ZIPFoundation

enum ZipError: LocalizedError {
    case extractionFailed(String)
    case jsonNotFound
    case invalidZipFile
    
    var errorDescription: String? {
        switch self {
        case .extractionFailed(let reason):
            return "Failed to extract ZIP: \(reason)"
        case .jsonNotFound:
            return "Could not find memories_history.json in the ZIP file"
        case .invalidZipFile:
            return "The file is not a valid ZIP archive"
        }
    }
}

class ZipService {
    static let shared = ZipService()
    
    private init() {}
    
    /// Extract ZIP file and return the path to the extracted folder
    func extractZip(from sourceURL: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fileManager = FileManager.default
                    
                    // Create a temporary directory for extraction
                    let tempDir = fileManager.temporaryDirectory
                        .appendingPathComponent("SnapMemories_\(UUID().uuidString)")
                    
                    try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    
                    // Extract the ZIP file
                    try fileManager.unzipItem(at: sourceURL, to: tempDir)
                    
                    continuation.resume(returning: tempDir)
                } catch {
                    continuation.resume(throwing: ZipError.extractionFailed(error.localizedDescription))
                }
            }
        }
    }
    
    /// Find the memories_history.json file in the extracted folder
    func findMemoriesJSON(in folder: URL) throws -> URL {
        let fileManager = FileManager.default
        
        // Search patterns - Snapchat exports can have different structures
        let possiblePaths = [
            folder.appendingPathComponent("json/memories_history.json"),
            folder.appendingPathComponent("memories_history.json"),
        ]
        
        // Check direct paths first
        for path in possiblePaths {
            if fileManager.fileExists(atPath: path.path) {
                return path
            }
        }
        
        // Search recursively if not found in expected locations
        if let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == "memories_history.json" {
                    return fileURL
                }
            }
        }
        
        throw ZipError.jsonNotFound
    }
    
    /// Parse the memories JSON file
    func parseMemoriesJSON(at url: URL) throws -> [Memory] {
        let data = try Data(contentsOf: url)
        let container = try JSONDecoder().decode(MemoriesContainer.self, from: data)
        return container.savedMedia
    }
    
    /// Clean up extracted files
    func cleanup(folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }
}
