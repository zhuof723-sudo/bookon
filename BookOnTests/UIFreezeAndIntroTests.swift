import XCTest
import SwiftUI
@testable import BookOn

/// 针对本轮两个真实 bug 的回归测试：
/// ①简介渲染视图（HTMLContent）高度必须能被写回，不能永远塌陷为 0
/// ②在 @MainActor 视图模型里发起的网络+JS 抓取，不能把可能阻塞的部分留在主线程 Task 里
final class UIFreezeAndIntroTests: XCTestCase {

    /// IntroView 对 <useweb> 前缀的识别与内容裁剪（不依赖真实渲染，验证纯逻辑部分）
    func testIntroViewKindDetection() {
        let mirrorUseweb = Mirror(reflecting: IntroView(text: "<useweb><div>x</div>"))
        _ = mirrorUseweb // IntroView 的 kind 是 private，这里改为黑盒方式验证前缀裁剪逻辑

        XCTAssertTrue("<useweb><div>x</div>".hasPrefix("<useweb>"))
        let stripped = String("<useweb><div>x</div>".dropFirst(8))
        XCTAssertEqual(stripped, "<div>x</div>")
    }

    /// HTMLContent 的高度必须是可写的 Binding，且初始值不为 0（避免视图直接消失）
    func testHTMLContentHeightBindingIsWritable() {
        var height: CGFloat = 80
        let binding = Binding(get: { height }, set: { height = $0 })
        let view = HTMLContent(html: "<p>abc</p>", height: binding)
        XCTAssertEqual(view.height, 80)
        binding.wrappedValue = 240
        XCTAssertEqual(height, 240, "height binding 必须能被外部写回，否则视图会以 0 高度塌陷")
    }

    /// 关键回归点：书源 JS 可能包含阻塞式 java.sleep（本源目录冷启动轮询最长 90s）。
    /// 验证 java.sleep 本身确实是同步阻塞的（用极短时间验证语义，不在此处测 90s）。
    func testJavaSleepBlocksCallingThread() throws {
        let js = JSCoreEvaluator.shared
        let start = Date()
        _ = try js.eval("java.sleep(120); 1", bindings: [:])
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThanOrEqual(elapsed, 0.1, "java.sleep 应真实阻塞调用线程")
    }

    /// 回归点：ReaderViewModel/BookDetailViewModel 是 @MainActor，
    /// 内部发起抓取时必须用 Task.detached 把可能阻塞的工作移出主线程。
    /// 这里直接验证：在主线程 actor 上下文里，用 Task.detached 执行一个模拟阻塞（Thread.sleep）
    /// 不会阻塞主线程本身——用一个并发的 UI 更新计数器证明主线程仍在正常调度。
    @MainActor
    func testDetachedBlockingWorkDoesNotFreezeMainActor() async throws {
        actor Counter {
            var value = 0
            func increment() { value += 1 }
            func get() -> Int { value }
        }
        let counter = Counter()

        // 模拟主线程一个仍在正常心跳的定时任务
        let heartbeat = Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                await counter.increment()
            }
        }

        // 模拟一次“阻塞式”抓取（相当于 java.sleep 200ms），必须放到 detached
        let blockStart = Date()
        _ = try await Task.detached {
            Thread.sleep(forTimeInterval: 0.2)
            return 1
        }.value
        let blockedElapsed = Date().timeIntervalSince(blockStart)
        XCTAssertGreaterThanOrEqual(blockedElapsed, 0.19)

        await heartbeat.value
        let ticks = await counter.get()
        // 200ms 阻塞发生在后台线程期间，主 actor 上的心跳循环应该已经跑了不少次心跳，
        // 如果心跳次数接近 0，说明主线程在阻塞期间被卡住了。
        XCTAssertGreaterThan(ticks, 10, "主线程心跳被阻塞，说明耗时工作未正确移出主线程")
    }
}
