<img width="900" height="628" alt="image" src="https://github.com/user-attachments/assets/1291bb8e-0969-4660-b9bd-c223e743b2a3" />

# Tinify - 图片压缩工具

一款 macOS 原生桌面图片压缩工具，支持 **Tinify API** 和 **本地压缩** 双模式，可批量压缩 PNG / JPG / WebP 图片。

## 功能特性

- **双压缩模式**：左上角一键切换 Tinify API 与本地压缩
- **批量处理**：选择输入文件夹，自动扫描所有可压缩图片
- **实时状态**：转圈（压缩中）、打钩（完成）、灰色（待处理），并显示压缩比
- **智能跳过**：输出目录中已存在同名文件则自动跳过，避免重复压缩
- **压缩前重命名**：可选开启，按 `前缀-时间戳-序号.ext` 格式统一命名
- **压缩后清理**：可选开启，压缩完毕自动将输入文件移至废纸篓
- **持久化配置**：API Key、文件夹路径、压缩模式、设置项均自动保存
- **安全作用域书签**：文件夹访问权限在 App 重启后依然有效

## 压缩模式说明

### Tinify 模式

使用 [Tinify API](https://tinypng.com/developers) 进行云端压缩，压缩效果优秀（通常 60-80% 体积缩减）。

- 需要填入 Tinify API Key（免费额度每月 500 张）
- 界面实时显示本月已用次数和剩余额度
- 支持 PNG、JPG/JPEG、WebP

### 本地模式

使用 macOS 原生 ImageIO 框架进行本地压缩，**无需网络、无次数限制**。

| 格式 | 压缩策略 | 预期效果 |
|------|---------|---------|
| JPG/JPEG | `CGImageDestination` + quality 0.7 | 60-80% 缩减 |
| PNG（无透明） | 自动转高质量 JPEG（quality 0.8） | 60-80% 缩减 |
| PNG（有透明） | 去除元数据后重新编码 | 10-30% 缩减 |
| WebP（无透明） | 转 JPEG（quality 0.75） | 视源文件而定 |
| WebP（有透明） | 转 PNG | 视源文件而定 |

> **注意**：本地模式下 PNG 有透明通道的图片压缩率有限。如需与 TinyPNG 同等效果，可手动添加 [pngquant.swift](https://github.com/awxkee/pngquant.swift) SPM 依赖并修改 `LocalCompressor.swift`。

## 技术架构

```
Tinify/
├── TinifyApp.swift            # App 入口
├── ContentView.swift          # 主界面（SwiftUI）
├── CompressorViewModel.swift  # 业务逻辑 & 状态管理
├── TinifyService.swift        # Tinify API 网络层
├── LocalCompressor.swift      # 本地压缩引擎
├── Tinify.entitlements        # 沙盒权限配置
└── Assets.xcassets/           # 图标资源
```

### 核心文件说明

#### `CompressorViewModel.swift`

主要的 ViewModel，采用 `@MainActor` + `ObservableObject` 模式：

- **状态持久化**：通过 `@AppStorage` 保存 API Key、文件夹路径、压缩模式等配置
- **文件夹权限**：使用 Security-Scoped Bookmarks（`URL.bookmarkData(options: .withSecurityScope)`）持久化用户选择的文件夹访问权限
- **压缩调度**：`startCompression()` 根据 `CompressionMode` 枚举分发到 `TinifyService` 或 `LocalCompressor`
- **文件扫描**：递归遍历输入文件夹，筛选 `.png` / `.jpg` / `.jpeg` / `.webp` 文件

关键数据模型：

```swift
enum CompressionMode: String, CaseIterable {
    case tinify = "Tinify"
    case local = "本地"
}

enum CompressionStatus: Equatable {
    case pending      // 待处理
    case compressing  // 压缩中
    case success      // 完成
    case error(String) // 失败
}

struct ImageFile: Identifiable {
    let id: UUID
    let url: URL
    var status: CompressionStatus
    var compressionRatio: Double?
}
```

#### `TinifyService.swift`

封装 Tinify REST API 的网络层：

- `compressImage(apiKey:fileURL:)` — 上传图片到 `/shrink` 端点，解析响应后下载压缩结果
- `fetchAccountUsage(apiKey:)` — 通过发送空请求获取 `Compression-Count` 响应头
- 使用 HTTP Basic Auth（`api:<key>` Base64 编码）
- 返回元组 `(data, originalSize, compressedSize, compressionCount)`

#### `LocalCompressor.swift`

基于 macOS 原生框架的本地压缩引擎：

- 使用 `CGImageSource` 读取图片
- 使用 `CGImageDestination` 重新编码，通过 `kCGImageDestinationLossyCompressionQuality` 控制 JPEG 质量
- 自动检测 Alpha 通道（`cgImage.alphaInfo`）决定输出格式
- 压缩后体积大于等于原始体积时自动回退为原始数据

#### `ContentView.swift`

SwiftUI 构建的主界面：

- 顶部分段 `Picker` 切换压缩模式
- Tinify 模式下显示 API Key 输入框和使用量统计
- 文件列表使用 `List` 展示，每个文件显示状态图标和压缩比
- 设置面板通过 `ZStack` overlay 实现居中弹出，点击背景关闭

### 沙盒权限 (`Tinify.entitlements`)

| 权限 | 用途 |
|------|------|
| `com.apple.security.app-sandbox` | 启用 App Sandbox |
| `com.apple.security.files.user-selected.read-write` | 读写用户选择的文件夹 |
| `com.apple.security.network.client` | Tinify API 网络请求 |

## 开发环境

- **平台**：macOS 15.0+
- **语言**：Swift 5
- **框架**：SwiftUI + ImageIO + Foundation
- **IDE**：Xcode 16.0+
- **无第三方依赖**（纯原生实现）

## 构建与运行

### 开发调试

在 Xcode 中打开 `Tinify.xcodeproj`，选择 `Tinify` scheme，点击运行即可。

### 导出 DMG

项目根目录提供了 `build_dmg.sh` 脚本，可一键打包为 DMG 安装包（无需付费 Apple 开发者账号）：

```bash
chmod +x build_dmg.sh
./build_dmg.sh
```

脚本流程：
1. `xcodebuild archive` — 以 Release 配置归档（跳过代码签名）
2. 从 `.xcarchive` 中提取 `.app`
3. `hdiutil create` — 生成包含 App 和 Applications 快捷方式的 DMG

> 首次打开未签名 App 时，需右键选择"打开"或在「系统设置 → 隐私与安全性」中允许运行。

## 使用说明

1. 启动 App，左上角选择压缩模式（Tinify 或 本地）
2. 如选择 Tinify 模式，输入 API Key（可在 [tinypng.com](https://tinypng.com/developers) 免费获取）
3. 点击「选择」按钮分别设置输入和输出文件夹
4. 文件列表自动显示输入文件夹中的所有图片
5. 可选：点击齿轮按钮开启「压缩前重命名」或「压缩后清理」
6. 点击「开始压缩」，实时查看每张图片的压缩进度和结果
