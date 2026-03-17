import Foundation
import SwiftUI

enum CompressionStatus: Equatable {
    case pending
    case compressing
    case success
    case error(String)
}

enum CompressionMode: String, CaseIterable {
    case tinify = "Tinify算法"
    case local = "本地算法"
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
    @AppStorage("compression_mode") var compressionModeRaw: String = CompressionMode.local.rawValue
    
    var compressionMode: CompressionMode {
        get { CompressionMode(rawValue: compressionModeRaw) ?? .local }
        set { compressionModeRaw = newValue.rawValue }
    }
    
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
        if compressionMode == .tinify {
            guard !apiKey.isEmpty else {
                alertMessage = "请输入 API Key"
                showAlert = true
                return
            }
        }
        guard let inputURL = inputFolderURL, let outputURL = outputFolderURL else { return }
        
        if inputURL.path == outputURL.path {
            alertMessage = "输入目录和输出目录不能相同，请选择不同的输出目录。"
            showAlert = true
            return
        }
        
        isCompressing = true
        
        Task {
            if renameEnabled {
                do {
                    try await renameInputFiles()
                    scanFiles()
                } catch {
                    alertMessage = "重命名失败: \(error.localizedDescription)"
                    showAlert = true
                    isCompressing = false
                    return
                }
            }
            
            for index in files.indices {
                if files[index].status == .success { continue }
                if index >= files.count { break }
                
                files[index].status = .compressing
                
                do {
                    let fileURL = files[index].url
                    
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
                    
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        files[index].status = .success
                        if let attr = try? FileManager.default.attributesOfItem(atPath: destinationURL.path),
                           let compressedSize = attr[.size] as? Int64,
                           let originalAttr = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                           let originalSize = originalAttr[.size] as? Int64,
                           originalSize > 0 {
                            files[index].compressionRatio = 1.0 - (Double(compressedSize) / Double(originalSize))
                        } else {
                            files[index].compressionRatio = 0
                        }
                        continue
                    }
                    
                    try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                    
                    let data: Data
                    let originalSize: Int
                    let compressedSize: Int
                    
                    switch compressionMode {
                    case .tinify:
                        let result = try await TinifyService.shared.compressImage(apiKey: apiKey, fileURL: fileURL)
                        data = result.data
                        originalSize = result.originalSize
                        compressedSize = result.compressedSize
                        if let newCount = result.compressionCount {
                            self.compressionCount = newCount
                        }
                    case .local:
                        let result = try await LocalCompressor.shared.compressImage(fileURL: fileURL)
                        data = result.data
                        originalSize = result.originalSize
                        compressedSize = result.compressedSize
                    }
                    
                    try data.write(to: destinationURL)
                    
                    files[index].status = .success
                    if originalSize > 0 {
                        files[index].compressionRatio = 1.0 - (Double(compressedSize) / Double(originalSize))
                    } else {
                        files[index].compressionRatio = 0
                    }
                    
                } catch {
                    files[index].status = .error(error.localizedDescription)
                }
            }
            
            if cleanInputAfterCompression {
                do {
                    try await cleanInputFiles()
                } catch {
                    self.alertMessage = "清理文件失败: \(error.localizedDescription)"
                    self.showAlert = true
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
