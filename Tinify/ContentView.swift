import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = CompressorViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Tinify 图片压缩工具")
                .font(.title)
                .padding(.top)
            
            // API Key
            HStack {
                Text("API Key:")
                SecureField("输入 Tinify API Key", text: $viewModel.apiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        viewModel.refreshCompressionCount()
                    }
                
                Button(action: {
                    viewModel.refreshCompressionCount()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新使用量")
            }
            .padding(.horizontal)
            
            // Usage Info
            if let count = viewModel.compressionCount {
                HStack {
                    Text("本月已用: \(count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("|")
                        .foregroundColor(.gray)
                    
                    let remaining = max(0, 500 - count)
                    Text("免费额度剩余: \(remaining)")
                        .font(.caption)
                        .foregroundColor(remaining < 50 ? .orange : .green)
                    
                    Spacer()
                }
                .padding(.horizontal)
            } else if !viewModel.apiKey.isEmpty {
                 HStack {
                    Text("正在获取使用量...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            // Folder Selection
            HStack {
                VStack(alignment: .leading) {
                    Text("输入文件夹:")
                        .font(.headline)
                    HStack {
                        Text(viewModel.inputFolderPath.isEmpty ? "未选择" : viewModel.inputFolderPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button("选择") {
                            selectFolder { url in
                                viewModel.inputFolderURL = url
                            }
                        }
                        
                        if !viewModel.inputFolderPath.isEmpty {
                            Button(action: {
                                NSWorkspace.shared.open(URL(fileURLWithPath: viewModel.inputFolderPath))
                            }) {
                                Image(systemName: "folder")
                            }
                            .help("打开文件夹")
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
                
                Spacer()
                
                VStack(alignment: .leading) {
                    Text("输出文件夹:")
                        .font(.headline)
                    HStack {
                        Text(viewModel.outputFolderPath.isEmpty ? "未选择" : viewModel.outputFolderPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button("选择") {
                            selectFolder { url in
                                viewModel.outputFolderURL = url
                            }
                        }
                        
                        if !viewModel.outputFolderPath.isEmpty {
                            Button(action: {
                                NSWorkspace.shared.open(URL(fileURLWithPath: viewModel.outputFolderPath))
                            }) {
                                Image(systemName: "folder")
                            }
                            .help("打开文件夹")
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // File List
            VStack(alignment: .leading) {
                HStack {
                    Text("文件列表 (\(viewModel.files.count))")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                
                List(viewModel.files) { file in
                    HStack {
                        Text(file.name)
                            .frame(width: 250, alignment: .leading)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        switch file.status {
                        case .pending:
                            Text("待处理")
                                .foregroundColor(.gray)
                        case .compressing:
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.5)
                                Text("压缩中...")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        case .success:
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                if let ratio = file.compressionRatio {
                                    if ratio == 0 {
                                        Text("已存在")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text(String(format: "-%.1f%%", ratio * 100))
                                            .font(.caption)
                                            .bold()
                                    }
                                }
                            }
                        case .error(let msg):
                            Text("失败: \(msg)")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            // Action Button
            Button(action: viewModel.startCompression) {
                Text(viewModel.isCompressing ? "正在压缩..." : "开始压缩")
                    .font(.headline)
                    .frame(width: 150, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isCompressing || viewModel.files.isEmpty || viewModel.outputFolderURL == nil)
            .padding(.bottom)
            .alert(isPresented: $viewModel.showAlert) {
                Alert(title: Text("提示"), message: Text(viewModel.alertMessage), dismissButton: .default(Text("确定")))
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .onAppear {
            viewModel.restoreFolders()
            viewModel.refreshCompressionCount()
        }
    }
    
    func selectFolder(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "选择文件夹"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                completion(url)
            }
        }
    }
}

#Preview {
    ContentView()
}
