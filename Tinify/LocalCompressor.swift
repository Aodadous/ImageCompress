import Foundation
import AppKit
import ImageIO

enum LocalCompressorError: Error, LocalizedError {
    case invalidImage
    case compressionFailed
    case unsupportedFormat(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无法读取图片"
        case .compressionFailed:
            return "压缩失败"
        case .unsupportedFormat(let fmt):
            return "本地模式暂不支持 \(fmt) 格式压缩"
        }
    }
}

class LocalCompressor {
    static let shared = LocalCompressor()
    private init() {}
    
    func compressImage(fileURL: URL) async throws -> (data: Data, originalSize: Int, compressedSize: Int) {
        let ext = fileURL.pathExtension.lowercased()
        let originalData = try Data(contentsOf: fileURL)
        let originalSize = originalData.count
        
        let compressedData: Data
        
        switch ext {
        case "jpg", "jpeg":
            compressedData = try compressJPEG(data: originalData, quality: 0.7)
        case "png":
            compressedData = try compressPNG(data: originalData)
        case "webp":
            compressedData = try compressWebP(data: originalData)
        default:
            throw LocalCompressorError.unsupportedFormat(ext)
        }
        
        return (compressedData, originalSize, compressedData.count)
    }
    
    // MARK: - JPEG Compression
    
    private func compressJPEG(data: Data, quality: CGFloat) throws -> Data {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw LocalCompressorError.invalidImage
        }
        
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else {
            throw LocalCompressorError.compressionFailed
        }
        
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImageDestinationOptimizeColorForSharing: true
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw LocalCompressorError.compressionFailed
        }
        
        return mutableData as Data
    }
    
    // MARK: - PNG Compression
    
    private func compressPNG(data: Data) throws -> Data {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw LocalCompressorError.invalidImage
        }
        
        let hasAlpha = cgImage.alphaInfo != .none && cgImage.alphaInfo != .noneSkipFirst && cgImage.alphaInfo != .noneSkipLast
        
        // For PNG without alpha, convert to high-quality JPEG for much better compression
        if !hasAlpha {
            return try compressJPEG(data: data, quality: 0.8)
        }
        
        // For PNG with alpha, re-encode stripping metadata
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else {
            throw LocalCompressorError.compressionFailed
        }
        
        // Don't copy metadata (strips EXIF, GPS, etc.)
        let addOptions: [CFString: Any] = [:]
        CGImageDestinationAddImage(destination, cgImage, addOptions as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw LocalCompressorError.compressionFailed
        }
        
        let result = mutableData as Data
        
        // If re-encoded PNG is larger than original (possible due to different encoder), keep original
        if result.count >= data.count {
            return data
        }
        
        return result
    }
    
    // MARK: - WebP Compression
    
    private func compressWebP(data: Data) throws -> Data {
        // macOS can read WebP via ImageIO but cannot write WebP natively.
        // Read as CGImage and re-encode as high-quality JPEG (lossy but effective).
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw LocalCompressorError.invalidImage
        }
        
        let hasAlpha = cgImage.alphaInfo != .none && cgImage.alphaInfo != .noneSkipFirst && cgImage.alphaInfo != .noneSkipLast
        
        // WebP with alpha -> PNG, WebP without alpha -> JPEG
        let uti = hasAlpha ? "public.png" as CFString : "public.jpeg" as CFString
        
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, uti, 1, nil) else {
            throw LocalCompressorError.compressionFailed
        }
        
        var options: [CFString: Any] = [:]
        if !hasAlpha {
            options[kCGImageDestinationLossyCompressionQuality] = 0.75
        }
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw LocalCompressorError.compressionFailed
        }
        
        let result = mutableData as Data
        if result.count >= data.count {
            return data
        }
        return result
    }
}
