import Foundation
import Photos
import CoreLocation
import UniformTypeIdentifiers

enum PhotosError: LocalizedError {
    case notAuthorized
    case saveFailed(String)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photo library access not authorized. Please enable in Settings."
        case .saveFailed(let reason):
            return "Failed to save to Photos: \(reason)"
        case .invalidData:
            return "Invalid image or video data"
        }
    }
}

class PhotosService {
    static let shared = PhotosService()
    
    private init() {}
    
    /// Request photo library authorization
    func requestAuthorization() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        
        guard status == .authorized || status == .limited else {
            throw PhotosError.notAuthorized
        }
    }
    
    /// Check current authorization status
    var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        return status == .authorized || status == .limited
    }
    
    /// Save photo to library with original creation date and location
    func savePhoto(
        data: Data,
        creationDate: Date?,
        location: CLLocation?,
        fileExtension: String
    ) async throws {
        guard !data.isEmpty else {
            throw PhotosError.invalidData
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                
                // Set the correct UTType based on file extension
                switch fileExtension.lowercased() {
                case "jpg", "jpeg":
                    options.uniformTypeIdentifier = UTType.jpeg.identifier
                case "png":
                    options.uniformTypeIdentifier = UTType.png.identifier
                case "heic":
                    options.uniformTypeIdentifier = UTType.heic.identifier
                case "webp":
                    options.uniformTypeIdentifier = UTType.webP.identifier
                default:
                    options.uniformTypeIdentifier = UTType.image.identifier
                }
                
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: options)
                
                // Set the original creation date - THIS IS THE KEY FEATURE
                if let date = creationDate {
                    request.creationDate = date
                }
                
                // Set location if available
                if let loc = location {
                    request.location = loc
                }
                
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotosError.saveFailed(error?.localizedDescription ?? "Unknown error"))
                }
            }
        }
    }
    
    /// Save video to library with original creation date and location
    func saveVideo(
        fileURL: URL,
        creationDate: Date?,
        location: CLLocation?
    ) async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw PhotosError.invalidData
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false  // Keep original file
                
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: fileURL, options: options)
                
                // Set the original creation date
                if let date = creationDate {
                    request.creationDate = date
                }
                
                // Set location if available
                if let loc = location {
                    request.location = loc
                }
                
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotosError.saveFailed(error?.localizedDescription ?? "Unknown error"))
                }
            }
        }
    }
}
