import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// UIKit 文件选择器（UIDocumentPickerViewController）的 SwiftUI 包装。
/// 相比 SwiftUI fileImporter：支持多选、能正确处理 iCloud/“文件”App 的安全域、
/// 在 iOS 16 上更稳定，且可自定义 asCopy。
struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType] = [.json, .plainText, .text, .data]
    var allowsMultiple = false
    var asCopy = true
    let onPick: ([URL]) -> Void
    var onCancel: () -> Void = {}

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: asCopy)
        picker.allowsMultipleSelection = allowsMultiple
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}

extension DocumentPicker {
    /// 读取选中文件内容（自动处理安全域访问）
    static func readText(_ url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        // 优先 UTF-8，失败再试 GBK（部分国内导出的文件）
        if let s = String(data: data, encoding: .utf8) { return s }
        let gbk = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gbk))
    }
}
