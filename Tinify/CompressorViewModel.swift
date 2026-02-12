import Foundation
import SwiftUI

enum CompressionStatus: Equatable {
    case pending
    case compressing
    case success
    case error(String)
}

struct ImageFile: Identifiable {
    let id = UUID()
    let url: URL
    var status: CompressionStatus = .pending
    var compressionRatio: Double? = nil
    
    var name: String {
        url.lastPathComponent
    }
}

@MainActor
class CompressorViewModel: ObservableObject {
    @AppStorage("tinify_api_key") var apiKey: String = ""
    @AppStorage("input_folder_path") var inputFolderPath: String = ""
    @AppStorage("output_folder_path") var outputFolderPath: String = ""
    @AppStorage("clean_input_after_compression") var cleanInputAfterCompression: Bool = false
    @AppStorage("rename_enabled") var renameEnabled: Bool = false
    @AppStorage("rename_prefix") var renamePrefix: String = "icon"
    
    @Published var isCompressing: Bool = false
    @Published var compressionCount: Int? = nil
    @Published var showAlert: Bool = false
    @Published var alertMessage: String = ""
    
    @Published var files: [ImageFile] = []
    
    var inputFolderURL: URL? {
        didSet {
            if let url = inputFolderURL {
                inputFolderPath = url.path
                saveBookmark(for: url, key: "input_folder_bookmark")
                scanFiles()
            }
        }
    }
    
    var outputFolderURL: URL? {
        didSet {
            if let url = outputFolderURL {
                outputFolderPath = url.path
                saveBookmark(for: url, key: "output_folder_bookmark")
            }
        }
    }
    
    func restoreFolders() {
        if let inputData = UserDefaults.standard.data(forKey: "input_folder_bookmark") {
            var isStale = false
            if let inputURL = try? URL(resolvingBookmarkData: inputData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if isStale {
                    saveBookmark(for: inputURL, key: "input_folder_bookmark")
                }
                if inputURL.startAccessingSecurityScopedResource() {
                    self.inputFolderURL = inputURL
                    // scanFiles() is called by didSet
                } else {
                    print("Could not access input folder resource")
                }
            }
        }
        
        if let outputData = UserDefaults.standard.data(forKey: "output_folder_bookmark") {
             var isStale = false
             if let outputURL = try? URL(resolvingBookmarkData: outputData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if isStale {
                    saveBookmark(for: outputURL, key: "output_folder_bookmark")
                }
                if outputURL.startAccessingSecurityScopedResource() {
                    self.outputFolderURL = outputURL
                } else {
                    print("Could not access output folder resource")
                }
            }
        }
    }
    
    private func saveBookmark(for url: URL, key: String) {
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("Failed to save bookmark for \(key): \(error)")
        }
    }
    
    func scanFiles() {
        guard let folder = inputFolderURL else { return }
        
        var newFiles: [ImageFile] = []
        let fileManager = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        
        if let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: nil, options: options) {
            for case let fileURL as URL in enumerator {
                if isImageFile(fileURL) {
                    newFiles.append(ImageFile(url: fileURL))
                }
            }
        }
        self.files = newFiles
    }
    
    private func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "webp"].contains(ext)
    }
    
    func startCompression() {
        guard !apiKey.isEmpty else {
            alertMessage = "请输入 API Key"
            showAlert = true
            return 
        }
        guard let inputURL = inputFolderURL, let outputURL = outputFolderURL else { return }
        
        isCompressing = true
        
        Task {
            // Handle renaming first if enabled
            if renameEnabled {
                do {
                    try await renameInputFiles()
                    // Re-scan files after rename
                    scanFiles() 
                } catch {
                    alertMessage = "重命名失败: \(error.localizedDescription)"
                    showAlert = true
                    isCompressing = false
                    return
                }
            }
            
            for index in files.indices {
                if files[index].status == .success { continue } // Skip already compressed
                
                // Stop if user cleared files or something changed (simplified check)
                if index >= files.count { break }
                
                files[index].status = .compressing
                
                do {
                    let fileURL = files[index].url
                    
                    // Calculate relative path
                    let inputPath = inputURL.path
                    let filePath = fileURL.path
                    
                    var relativePath = filePath
                    if filePath.hasPrefix(inputPath) {
                        relativePath = String(filePath.dropFirst(inputPath.count))
                    }
                    if relativePath.hasPrefix("/") {
                        relativePath = String(relativePath.dropFirst())
                    }
                    
                    let destinationURL = outputURL.appendingPathComponent(relativePath)
                    
                    // Check if file already exists
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        files[index].status = .success
                        // Try to calculate ratio if possible
                        if let attr = try? FileManager.default.attributesOfItem(atPath: destinationURL.path),
                           let compressedSize = attr[.size] as? Int64,
                           let originalAttr = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                           let originalSize = originalAttr[.size] as? Int64,
                           originalSize > 0 {
                            files[index].compressionRatio = 1.0 - (Double(compressedSize) / Double(originalSize))
                        } else {
                            files[index].compressionRatio = 0
                        }
                        continue // Skip compression
                    }
                    
                    try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                    
                    let (data, originalSize, compressedSize, count) = try await TinifyService.shared.compressImage(apiKey: apiKey, fileURL: fileURL)
                    
                    try data.write(to: destinationURL)
                    
                    files[index].status = .success
                    if originalSize > 0 {
                        files[index].compressionRatio = 1.0 - (Double(compressedSize) / Double(originalSize))
                    } else {
                        files[index].compressionRatio = 0
                    }
                    
                    if let newCount = count {
                        self.compressionCount = newCount
                    }
                    
                } catch {
                    files[index].status = .error(error.localizedDescription)
                }
            }
            
            if cleanInputAfterCompression {
                do {
                    try await cleanInputFiles()
                    await MainActor.run {
                        // self.files = [] // Keep files in list
                        // No alert
                    }
                } catch {
                    await MainActor.run {
                        self.alertMessage = "清理文件失败: \(error.localizedDescription)"
                        self.showAlert = true
                    }
                }
            } else {
                await MainActor.run {
                     // Just finish
                }
            }
            
            isCompressing = false
        }
    }
    
    private func renameInputFiles() async throws {
        guard let inputURL = inputFolderURL else { return }
        let fileManager = FileManager.default
        let prefix = renamePrefix.isEmpty ? "icon" : renamePrefix
        
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        
        // Collect URLs first
        var fileURLs: [URL] = []
        if let enumerator = fileManager.enumerator(at: inputURL, includingPropertiesForKeys: nil, options: options) {
            for case let fileURL as URL in enumerator {
                if isImageFile(fileURL) {
                    fileURLs.append(fileURL)
                }
            }
        }
        
        // Sort
        fileURLs.sort { $0.lastPathComponent < $1.lastPathComponent }
        
        let timestamp = Int(Date().timeIntervalSince1970)
        
        for (index, fileURL) in fileURLs.enumerated() {
            let ext = fileURL.pathExtension
            let newName = "\(prefix)-\(timestamp)-\(index + 1).\(ext)"
            let newURL = fileURL.deletingLastPathComponent().appendingPathComponent(newName)
            
            try fileManager.moveItem(at: fileURL, to: newURL)
        }
    }
    
    private func cleanInputFiles() async throws {
         guard let inputURL = inputFolderURL else { return }
         let fileManager = FileManager.default
         
         let contents = try fileManager.contentsOfDirectory(at: inputURL, includingPropertiesForKeys: nil)
         for url in contents {
             try fileManager.trashItem(at: url, resultingItemURL: nil)
         }
    }
    
    func refreshCompressionCount() {
        guard !apiKey.isEmpty else { return }
        Task {
            do {
                let count = try await TinifyService.shared.fetchAccountUsage(apiKey: apiKey)
                self.compressionCount = count
            } catch {
                print("Failed to fetch count: \(error)")
                self.compressionCount = nil
            }
        }
    }
}
