import Foundation

enum TinifyError: Error {
    case invalidURL
    case fileReadError
    case apiError(String)
    case networkError(Error)
    case noData
}

struct TinifyResponse: Codable {
    let input: FileInfo
    let output: OutputInfo
    
    struct FileInfo: Codable {
        let size: Int
        let type: String
    }
    
    struct OutputInfo: Codable {
        let size: Int
        let type: String
        let width: Int?
        let height: Int?
        let url: String
    }
}

class TinifyService {
    static let shared = TinifyService()
    private init() {}
    
    func compressImage(apiKey: String, fileURL: URL) async throws -> (data: Data, originalSize: Int, compressedSize: Int, compressionCount: Int?) {
        // 1. Prepare Request
        guard let url = URL(string: "https://api.tinify.com/shrink") else {
            throw TinifyError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Basic Auth
        let loginString = "api:\(apiKey)"
        guard let loginData = loginString.data(using: .utf8) else {
            throw TinifyError.apiError("Invalid API Key format")
        }
        let base64LoginString = loginData.base64EncodedString()
        request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        
        // Read file data
        guard let fileData = try? Data(contentsOf: fileURL) else {
            throw TinifyError.fileReadError
        }
        request.httpBody = fileData
        
        // 2. Send Shrink Request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TinifyError.apiError("Invalid response")
        }
        
        // Extract Compression-Count
        let count = httpResponse.value(forHTTPHeaderField: "Compression-Count").flatMap { Int($0) }
        
        if httpResponse.statusCode == 401 {
             throw TinifyError.apiError("Unauthorized: Check your API Key")
        }
        
        guard httpResponse.statusCode == 201 else {
            // Try to parse error message
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String {
                throw TinifyError.apiError(message)
            }
            throw TinifyError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        // 3. Parse Response
        let tinifyResponse = try JSONDecoder().decode(TinifyResponse.self, from: data)
        guard let downloadURL = URL(string: tinifyResponse.output.url) else {
            throw TinifyError.apiError("Invalid download URL")
        }
        
        // 4. Download Compressed Image
        var downloadRequest = URLRequest(url: downloadURL)
        downloadRequest.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        
        let (compressedData, downloadResp) = try await URLSession.shared.data(for: downloadRequest)
        
        guard let downloadHttpResp = downloadResp as? HTTPURLResponse, downloadHttpResp.statusCode == 200 else {
            throw TinifyError.apiError("Failed to download compressed image")
        }
        
        return (compressedData, tinifyResponse.input.size, tinifyResponse.output.size, count)
    }
    
    func fetchAccountUsage(apiKey: String) async throws -> Int {
        guard let url = URL(string: "https://api.tinify.com/shrink") else {
            throw TinifyError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let loginString = "api:\(apiKey)"
        guard let loginData = loginString.data(using: .utf8) else {
            throw TinifyError.apiError("Invalid API Key format")
        }
        let base64LoginString = loginData.base64EncodedString()
        request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        
        // Send empty body to trigger 400 but get header
        request.httpBody = Data()
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TinifyError.apiError("Invalid response")
        }
        
        if httpResponse.statusCode == 401 {
             throw TinifyError.apiError("Unauthorized: Check your API Key")
        }
        
        // Even 400 Bad Request contains the header if auth is correct
        if let countStr = httpResponse.value(forHTTPHeaderField: "Compression-Count"),
           let count = Int(countStr) {
            return count
        }
        
        throw TinifyError.apiError("Could not retrieve compression count")
    }
}
