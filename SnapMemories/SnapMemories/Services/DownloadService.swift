import Foundation
import UIKit
import ZIPFoundation
import AVFoundation

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
    
    private let maxRetries = 3
    private let retryDelay: UInt64 = 2_000_000_000 // 2 seconds in nanoseconds

    /// Download media from Snapchat CDN with automatic retry for transient failures
    /// - Parameter memory: The memory to download
    /// - Returns: Tuple of (data, fileExtension)
    func downloadMemory(_ memory: Memory) async throws -> (Data, String) {
        guard let url = URL(string: memory.mediaDownloadUrl) else {
            throw DownloadError.invalidURL
        }

        var lastError: Error = DownloadError.invalidResponse

        for attempt in 1...maxRetries {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw DownloadError.invalidResponse
                }

                // Retry on 403 (rate limit/expired token) or 5xx (server errors)
                if httpResponse.statusCode == 403 || (500...599).contains(httpResponse.statusCode) {
                    lastError = DownloadError.httpError(httpResponse.statusCode)
                    if attempt < maxRetries {
                        try await Task.sleep(nanoseconds: retryDelay * UInt64(attempt))
                        continue
                    }
                    throw lastError
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw DownloadError.httpError(httpResponse.statusCode)
                }

                guard !data.isEmpty else {
                    throw DownloadError.noData
                }

                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                var fileExtension = detectFileExtension(from: httpResponse, data: data, isVideo: memory.isVideo)
                var finalData = data

                #if DEBUG
                print("Download \(memory.displayDate): Content-Type=\(contentType), detected=\(fileExtension), size=\(data.count) bytes")
                #endif

                // If CDN returned a ZIP (overlay + main bundled), extract the main media file
                if contentType.contains("zip") || isZipData(data) {
                    #if DEBUG
                    print("ZIP detected for \(memory.displayDate), extracting main media...")
                    #endif
                    if let extracted = await extractMainMediaFromZip(data: data, isVideo: memory.isVideo) {
                        finalData = extracted.data
                        fileExtension = extracted.fileExtension
                        #if DEBUG
                        print("Extracted \(fileExtension) from ZIP, size=\(finalData.count) bytes")
                        #endif
                    }
                }

                // Convert WebP to JPEG since Photos framework rejects raw WebP data
                if fileExtension == "webp", let converted = convertWebPToJPEG(data: data) {
                    #if DEBUG
                    print("Converted WebP to JPEG for \(memory.displayDate)")
                    #endif
                    finalData = converted
                    fileExtension = "jpg"
                }

                return (finalData, fileExtension)

            } catch let error as DownloadError {
                lastError = error
                // Only retry on rate limit / server errors
                if case .httpError(let code) = error, (code == 403 || (500...599).contains(code)) {
                    if attempt < maxRetries {
                        try await Task.sleep(nanoseconds: retryDelay * UInt64(attempt))
                        continue
                    }
                }
                throw error
            } catch {
                lastError = DownloadError.networkError(error.localizedDescription)
                // Retry on network errors (timeouts, connection resets)
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: retryDelay * UInt64(attempt))
                    continue
                }
                throw lastError
            }
        }

        throw lastError
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

            // WebP: RIFF....WEBP
            if bytes.count >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46
                && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
                return "webp"
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

    /// Check if data starts with ZIP magic bytes (PK\x03\x04)
    private func isZipData(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let bytes = [UInt8](data.prefix(4))
        return bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04
    }

    /// Extract media from a ZIP bundle returned by Snapchat CDN.
    /// Composites the overlay (stickers/filters) onto the main image when both are present.
    private func extractMainMediaFromZip(data: Data, isVideo: Bool) async -> (data: Data, fileExtension: String)? {
        do {
            // Write ZIP data to temp file
            let tempZipURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).zip")
            try data.write(to: tempZipURL)
            defer { try? FileManager.default.removeItem(at: tempZipURL) }

            // Extract to temp directory
            let extractDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("snap_extract_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: extractDir) }

            try FileManager.default.unzipItem(at: tempZipURL, to: extractDir)

            let contents = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)

            // Find main and overlay files
            let mainFileURL = contents.first(where: { $0.lastPathComponent.contains("main") })
                ?? contents.first(where: { !$0.lastPathComponent.contains("overlay") })
            let overlayFileURL = contents.first(where: { $0.lastPathComponent.contains("overlay") })

            guard let mainFileURL = mainFileURL else { return nil }
            var mainData = try Data(contentsOf: mainFileURL)
            if isZipData(mainData) { return nil }

            // Detect main file format
            var detectedExt = detectFileExtension(from: HTTPURLResponse(), data: mainData, isVideo: isVideo)
            if detectedExt == "webp", let converted = convertWebPToJPEG(data: mainData) {
                mainData = converted
                detectedExt = "jpg"
            }

            // Composite the overlay on top if it exists
            if let overlayFileURL = overlayFileURL {
                var overlayData = try Data(contentsOf: overlayFileURL)

                // Convert overlay from WebP to PNG (preserving alpha/transparency).
                // JPEG would destroy the alpha channel, making the overlay solid white.
                let overlayExt = detectFileExtension(from: HTTPURLResponse(), data: overlayData, isVideo: false)
                if overlayExt == "webp", let image = UIImage(data: overlayData), let pngData = image.pngData() {
                    overlayData = pngData
                }

                if isVideo {
                    // Composite overlay onto video using custom AVVideoCompositing
                    if let compositedURL = try await compositeVideoOverlay(videoData: mainData, overlayData: overlayData) {
                        let compositedData = try Data(contentsOf: compositedURL)
                        try? FileManager.default.removeItem(at: compositedURL)
                        #if DEBUG
                        print("Composited overlay onto video")
                        #endif
                        return (compositedData, "mp4")
                    }
                } else {
                    // Composite overlay onto image
                    if let composited = compositeOverlay(mainData: mainData, overlayData: overlayData) {
                        #if DEBUG
                        print("Composited overlay onto main image")
                        #endif
                        return (composited, "jpg")
                    }
                }
            }

            let ext = detectedExt.isEmpty ? (isVideo ? "mp4" : "jpg") : detectedExt
            return (mainData, ext)
        } catch {
            #if DEBUG
            print("Failed to extract ZIP: \(error.localizedDescription)")
            #endif
        }
        return nil
    }

    /// Composite an overlay image on top of a video using AVAssetReader/Writer
    /// with a custom per-frame Core Graphics composite (no CALayer, no CoreAnimation).
    private func compositeVideoOverlay(videoData: Data, overlayData: Data) async throws -> URL? {
        guard let overlayUIImage = UIImage(data: overlayData),
              let overlayCGImage = overlayUIImage.cgImage else { return nil }

        // Write video to temp file
        let tempVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mp4")
        try videoData.write(to: tempVideoURL)

        let asset = AVURLAsset(url: tempVideoURL)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            try? FileManager.default.removeItem(at: tempVideoURL)
            return nil
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)

        // Display size after applying the rotation transform
        let transformedSize = naturalSize.applying(preferredTransform)
        let displaySize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

        // The pixel buffers from the reader are at naturalSize (pre-rotation).
        // The overlay was designed for the display orientation (post-rotation).
        // Pre-rotate the overlay into the native frame orientation using the inverse transform.
        let rotatedOverlayCG: CGImage? = {
            let renderer = UIGraphicsImageRenderer(size: naturalSize)
            let img = renderer.image { ctx in
                ctx.cgContext.concatenate(preferredTransform.inverted())
                UIImage(cgImage: overlayCGImage).draw(in: CGRect(origin: .zero, size: displaySize))
            }
            return img.cgImage
        }()

        guard let rotatedOverlayCG = rotatedOverlayCG else { return nil }

        let nw = Int(naturalSize.width)
        let nh = Int(naturalSize.height)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)_overlay.mp4")

        // --- Asset Reader ---
        let reader = try AVAssetReader(asset: asset)

        let videoReaderSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderSettings)
        reader.add(videoReaderOutput)

        // Audio reader (optional)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audioReaderOutput: AVAssetReaderTrackOutput?
        if let audioTrack = audioTracks.first {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM
            ]
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioSettings)
            reader.add(output)
            audioReaderOutput = output
        }

        // --- Asset Writer ---
        // Output at naturalSize (matching pixel buffer dimensions).
        // The preferredTransform metadata tells players how to rotate for display.
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoWriterSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: nw,
            AVVideoHeightKey: nh
        ]
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoWriterSettings)
        videoWriterInput.transform = preferredTransform

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: nw,
            kCVPixelBufferHeightKey as String: nh
        ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        writer.add(videoWriterInput)

        var audioWriterInput: AVAssetWriterInput?
        if audioReaderOutput != nil {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            writer.add(input)
            audioWriterInput = input
        }

        // Start reading and writing
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Process video frames on a background queue
        let result: Bool = await withCheckedContinuation { continuation in
            let videoQueue = DispatchQueue(label: "com.snapmemories.videoComposite")
            let audioQueue = DispatchQueue(label: "com.snapmemories.audioComposite")

            let group = DispatchGroup()

            // Process video frames
            group.enter()
            videoWriterInput.requestMediaDataWhenReady(on: videoQueue) {
                while videoWriterInput.isReadyForMoreMediaData {
                    guard reader.status == .reading,
                          let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() else {
                        videoWriterInput.markAsFinished()
                        group.leave()
                        return
                    }

                    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        videoWriterInput.markAsFinished()
                        group.leave()
                        return
                    }

                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                    // Draw the pre-rotated overlay onto each frame
                    CVPixelBufferLockBaseAddress(pixelBuffer, [])

                    let width = CVPixelBufferGetWidth(pixelBuffer)
                    let height = CVPixelBufferGetHeight(pixelBuffer)
                    let colorSpace = CGColorSpaceCreateDeviceRGB()
                    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

                    if let context = CGContext(
                        data: CVPixelBufferGetBaseAddress(pixelBuffer),
                        width: width,
                        height: height,
                        bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                        space: colorSpace,
                        bitmapInfo: bitmapInfo.rawValue
                    ) {
                        // The video frame is already in the pixel buffer.
                        // Draw the pre-rotated overlay on top (matches native orientation).
                        context.setBlendMode(.normal)
                        let rect = CGRect(x: 0, y: 0, width: width, height: height)
                        context.draw(rotatedOverlayCG, in: rect)
                    }

                    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

                    pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                }
            }

            // Process audio samples
            if let audioWriterInput = audioWriterInput, let audioReaderOutput = audioReaderOutput {
                group.enter()
                audioWriterInput.requestMediaDataWhenReady(on: audioQueue) {
                    while audioWriterInput.isReadyForMoreMediaData {
                        guard reader.status == .reading,
                              let sampleBuffer = audioReaderOutput.copyNextSampleBuffer() else {
                            audioWriterInput.markAsFinished()
                            group.leave()
                            return
                        }
                        audioWriterInput.append(sampleBuffer)
                    }
                }
            }

            group.notify(queue: .main) {
                writer.finishWriting {
                    continuation.resume(returning: writer.status == .completed)
                }
            }
        }

        // Clean up
        try? FileManager.default.removeItem(at: tempVideoURL)

        if result {
            #if DEBUG
            print("Video overlay composite complete: \(outputURL.lastPathComponent)")
            #endif
            return outputURL
        } else {
            #if DEBUG
            print("Video export failed: \(writer.error?.localizedDescription ?? "unknown")")
            #endif
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
    }

    /// Composite an overlay image on top of a main image using Core Graphics
    private func compositeOverlay(mainData: Data, overlayData: Data) -> Data? {
        guard let mainImage = UIImage(data: mainData),
              let overlayImage = UIImage(data: overlayData) else {
            return nil
        }

        let size = mainImage.size
        let renderer = UIGraphicsImageRenderer(size: size)

        let composited = renderer.image { context in
            // Draw main image
            mainImage.draw(in: CGRect(origin: .zero, size: size))
            // Draw overlay on top (scaled to fit main image dimensions)
            overlayImage.draw(in: CGRect(origin: .zero, size: size))
        }

        return composited.jpegData(compressionQuality: 0.95)
    }

    /// Convert WebP data to JPEG using UIImage (supports WebP on iOS 14+)
    private func convertWebPToJPEG(data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return image.jpegData(compressionQuality: 0.95)
    }

    /// Check if download URLs have expired by inspecting the `ts` query parameter
    /// - Parameter memories: Array of memories to check
    /// - Returns: `true` if URLs appear expired, `false` otherwise
    func checkUrlExpiration(_ memories: [Memory]) -> Bool {
        let sampled = memories.prefix(5)
        let now = Date().timeIntervalSince1970
        var checkedAny = false

        for memory in sampled {
            guard let components = URLComponents(string: memory.mediaDownloadUrl),
                  let tsValue = components.queryItems?.first(where: { $0.name == "ts" })?.value,
                  let ts = Double(tsValue) else {
                continue
            }
            checkedAny = true
            if ts < now {
                return true
            }
        }

        // If no URLs had a parseable `ts` parameter, we can't determine
        // expiration from the URL alone — fall back to a network probe
        if !checkedAny {
            return false // will be handled by async check
        }

        return false
    }

    /// Async expiration check: probes a download URL to verify it's still accessible
    /// - Parameter memories: Array of memories to check
    /// - Returns: `true` if URLs appear expired, `false` otherwise
    func checkUrlExpirationAsync(_ memories: [Memory]) async -> Bool {
        // First try the fast timestamp-based check
        if checkUrlExpiration(memories) {
            return true
        }

        // Fall back to probing a URL with a HEAD request
        guard let firstMemory = memories.first,
              let url = URL(string: firstMemory.mediaDownloadUrl) else {
            return false
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 10

            let (_, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                // 403/410 typically mean expired links
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 410 {
                    return true
                }
            }
        } catch {
            // Network error likely means the URL is no longer valid
            return true
        }

        return false
    }
}
