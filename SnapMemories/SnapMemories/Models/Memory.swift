import Foundation
import CoreLocation

// MARK: - Memory Model

struct Memory: Codable, Identifiable, Hashable {
    let id: UUID
    let date: String
    let mediaType: String
    let location: String?
    let downloadLink: String
    let mediaDownloadUrl: String
    
    // Not persisted - runtime state
    var isSelected: Bool = true
    var downloadStatus: DownloadStatus = .pending
    
    enum DownloadStatus: Equatable {
        case pending
        case downloading
        case completed
        case failed(String)
        case skippedDuplicate
    }
    
    enum CodingKeys: String, CodingKey {
        case date = "Date"
        case mediaType = "Media Type"
        case location = "Location"
        case downloadLink = "Download Link"
        case mediaDownloadUrl = "Media Download Url"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.date = try container.decode(String.self, forKey: .date)
        self.mediaType = try container.decode(String.self, forKey: .mediaType)
        self.location = try container.decodeIfPresent(String.self, forKey: .location)
        self.downloadLink = try container.decode(String.self, forKey: .downloadLink)
        self.mediaDownloadUrl = try container.decode(String.self, forKey: .mediaDownloadUrl)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(downloadLink, forKey: .downloadLink)
        try container.encode(mediaDownloadUrl, forKey: .mediaDownloadUrl)
    }
    
    // MARK: - Computed Properties
    
    var isVideo: Bool {
        mediaType.lowercased() == "video"
    }
    
    var isImage: Bool {
        mediaType.lowercased() == "image"
    }
    
    /// Parse date string "2026-01-21 15:43:47 UTC" to Date
    var parsedDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: date)
    }
    
    /// Formatted date for display
    var displayDate: String {
        guard let parsed = parsedDate else { return date }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: parsed)
    }
    
    /// Parse location string "Latitude, Longitude: 52.60789, -1.994181"
    var coordinates: CLLocationCoordinate2D? {
        guard let location = location else { return nil }
        
        // Handle "Latitude, Longitude: 0.0, 0.0" case
        let pattern = #"Latitude, Longitude: ([-\d.]+), ([-\d.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: location, range: NSRange(location.startIndex..., in: location)) else {
            return nil
        }
        
        guard let latRange = Range(match.range(at: 1), in: location),
              let lonRange = Range(match.range(at: 2), in: location),
              let lat = Double(location[latRange]),
              let lon = Double(location[lonRange]) else {
            return nil
        }
        
        // Skip 0,0 coordinates (no location data)
        if lat == 0.0 && lon == 0.0 {
            return nil
        }
        
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    var clLocation: CLLocation? {
        guard let coords = coordinates else { return nil }
        return CLLocation(latitude: coords.latitude, longitude: coords.longitude)
    }
    
    /// Unique hash for duplicate detection
    var uniqueHash: String {
        // Combine date and media URL for unique identification
        let combined = "\(date)_\(mediaDownloadUrl)"
        return combined.data(using: .utf8)?.base64EncodedString() ?? combined
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Memory, rhs: Memory) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Container for JSON Parsing

struct MemoriesContainer: Codable {
    let savedMedia: [Memory]
    
    enum CodingKeys: String, CodingKey {
        case savedMedia = "Saved Media"
    }
}

// MARK: - Import State

enum ImportState: Equatable {
    case idle
    case selectingFile
    case extractingZip
    case parsingJSON
    case ready
    case downloading(progress: Double, current: String)
    case complete(successful: Int, failed: Int, skipped: Int)
    case error(String)
    
    static func == (lhs: ImportState, rhs: ImportState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.selectingFile, .selectingFile),
             (.extractingZip, .extractingZip), (.parsingJSON, .parsingJSON),
             (.ready, .ready):
            return true
        case let (.downloading(p1, c1), .downloading(p2, c2)):
            return p1 == p2 && c1 == c2
        case let (.complete(s1, f1, sk1), .complete(s2, f2, sk2)):
            return s1 == s2 && f1 == f2 && sk1 == sk2
        case let (.error(e1), .error(e2)):
            return e1 == e2
        default:
            return false
        }
    }
}
