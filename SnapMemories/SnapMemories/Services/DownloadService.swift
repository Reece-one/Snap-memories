import Foundation

enum DownloadError: LocalizedError {
    case invalidURL
    case networkError(String)
    case invalidResponse
    case httpError(Int)
    case noData
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid download URL"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .noData:
            return "No data received"
        }
    }
}

class DownloadService {
    static let shared = DownloadService()
    
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    /// Download media from Snapchat CDN
    /// - Parameter memory: The memory to download
    /// - Returns: Tuple of (data, fileExtension)
    func downloadMemory(_ memory: Memory) async throws -> (Data, String) {
        guard let url = URL(string: memory.mediaDownloadUrl) else {
            throw DownloadError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add headers that might be expected by Snapchat CDN
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DownloadError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw DownloadError.httpError(httpResponse.statusCode)
            }
            
            guard !data.isEmpty else {
                throw DownloadError.noData
            }
            
            let fileExtension = detectFileExtension(from: httpResponse, data: data, isVideo: memory.isVideo)
            
            return (data, fileExtension)
            
        } catch let error as DownloadError {
            throw error
        } catch {
            throw DownloadError.networkError(error.localizedDescription)
        }
    }
    
    /// Detect file extension from response headers or data magic bytes
    private func detectFileExtension(from response: HTTPURLResponse, data: Data, isVideo: Bool) -> String {
        // Try Content-Type header first
        if let contentType = response.value(forHTTPHeaderField: "Content-Type") {
            switch contentType.lowercased() {
            case let ct where ct.contains("jpeg") || ct.contains("jpg"):
                return "jpg"
            case let ct where ct.contains("png"):
                return "png"
            case let ct where ct.contains("heic"):
                return "heic"
            case let ct where ct.contains("mp4"):
                return "mp4"
            case let ct where ct.contains("quicktime") || ct.contains("mov"):
                return "mov"
            case let ct where ct.contains("webp"):
                return "webp"
            default:
                break
            }
        }
        
        // Try magic bytes
        if data.count >= 4 {
            let bytes = [UInt8](data.prefix(12))
            
            // JPEG: FF D8 FF
            if bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
                return "jpg"
            }
            
            // PNG: 89 50 4E 47
            if bytes.count >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
                return "png"
            }
            
            // MP4/MOV: ftyp at offset 4
            if bytes.count >= 8 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
                return "mp4"
            }
            
            // HEIC: ftyp heic/mif1
            if bytes.count >= 12 {
                let ftypRange = Data(bytes[4..<8])
                if ftypRange == Data([0x66, 0x74, 0x79, 0x70]) {
                    let brandRange = Data(bytes[8..<12])
                    if brandRange == Data("heic".utf8) || brandRange == Data("mif1".utf8) {
                        return "heic"
                    }
                }
            }
        }
        
        // Fallback based on media type
        return isVideo ? "mp4" : "jpg"
    }
    
    /// Save data to temporary file (needed for videos)
    func saveToTemporaryFile(data: Data, extension ext: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(UUID().uuidString).\(ext)"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try data.write(to: fileURL)
        return fileURL
    }
    
    /// Clean up temporary file
    func cleanupTemporaryFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
