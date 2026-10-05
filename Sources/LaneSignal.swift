// LaneSignal.swift —— 总部共享（~/Dev/tools/dev/lib/tools/macapp/swift-shared/，产品仓 Shared/ 下放逐字节副本）
//
// 平台验收车道（Chapter 的 launch_<平台> 与 sop.measure，经共享 sim_lane）和 App 之间的契约，五个平台同一份：
// App 只需在「第一屏有数据的界面」onAppear 时调 LaneSignal.ready("<屏名>")，Mac 端在 App 里挂
// `@NSApplicationDelegateAdaptor(LaneAppDelegate.self)`，并在根视图 .task 里调 applyOrientation()/applyWindowFrame()。
// 不传 -lane_* 启动参数时什么都不做，生产路径零变化。2026-10-02 成长小金库首用。
import Foundation
import os
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 给平台验收车道（模拟器上的 sim_lane 与性能测量）留的两个口子，生产路径上不改变任何行为。
///
/// ① `lane-ready`：第一屏有数据的界面出现时打一行系统日志（subsystem = bundle id，category = lane）。
///    车道拿它当「起来了」的信号，比「截图和开机时不一样」可靠 —— Vision Pro 的房间背景本身就花，
///    手表黑底也会被当成空白。它只打一次；1.3 秒后再打一行 `lane-settled`：
///    首屏常有数字滚动、图表展开这类入场动画，要截干净的图就等这一行。
/// ② `-lane_orientation landscape`：simctl 转不了模拟器的方向，iPad 横屏截图只能由 App 自己请求。
///    只认 iPad；iPhone、Mac、手表、Vision 上一律忽略。和 -api_base 一样，不传就什么都不发生。
/// ③ `-lane_window 1440x900`：只认 Mac。商店截图要 2880×1800，就是 1440×900 点的窗口（含标题栏）落在 2 倍屏上；
///    App 把自己的窗口设成这个尺寸，挪到放得下它的屏里倍数最高的那块（都放不下就留在原屏）。
///    只动自己刚开的窗口，不激活、不置前 —— 本机外接屏是 1 倍，窗口落在那儿截出来只有一半像素。
/// ④ `-lane_quiet YES`：只认 Mac。车道（sim_lane 的 Mac 线、性能测量）在本人用电脑时也会跑，窗口一闪、Dock 冒图标
///    都打扰人（2026-10-02 本人：「mac 启动很多次」）。静默时进程是 accessory（不进 Dock、不占菜单栏），
///    窗口全透明、不接鼠标、挪到屏外；调用方再配 `open -g -j`（隐藏启动），窗口从头到尾不上屏。
///    `-lane_window` 在静默时改设内容区尺寸；`-lane_snapshot <png>` 在 lane-settled 时由 App 进程内离屏渲染
///    （与 Chapter 自测同法：cacheDisplay）按 2 倍写出，不靠屏幕截图。
enum LaneSignal {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lane",
                                    category: "lane")
    @MainActor private static var announced = false

    @MainActor static func ready(_ screen: String) {
        guard !announced else { return }
        announced = true
        log.notice("lane-ready \(screen, privacy: .public)")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.3))
            log.notice("lane-settled \(screen, privacy: .public)")
            #if os(macOS)
            writeSnapshotIfAsked()
            #endif
        }
    }

    @MainActor static func applyOrientation() {
        #if os(iOS)
        guard UserDefaults.standard.string(forKey: "lane_orientation") == "landscape",
              UIDevice.current.userInterfaceIdiom == .pad else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
                log.error("lane-orientation \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
    }

    @MainActor static func applyWindowFrame() {
        #if os(macOS)
        guard let spec = UserDefaults.standard.string(forKey: "lane_window") else { return }
        let parts = spec.lowercased().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] >= 400, parts[1] >= 300 else { return }
        let size = CGSize(width: parts[0], height: parts[1])
        Task { @MainActor in
            for _ in 0..<30 {   // 窗口在第一帧之后才挂上来
                if quiet, let window = laneWindow {
                    window.setContentSize(size)      // 静默：窗口不上屏，按内容区出图，正好 2 倍 = 商店尺寸
                    log.notice("lane-window \(Int(size.width))x\(Int(size.height)) content, quiet")
                    return
                }
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
                    let fits = NSScreen.screens.filter {
                        $0.visibleFrame.width >= size.width && $0.visibleFrame.height >= size.height
                    }
                    let screen = fits.max { $0.backingScaleFactor < $1.backingScaleFactor } ?? window.screen
                    let area = screen?.visibleFrame ?? window.frame
                    window.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                                           width: size.width, height: size.height), display: true)
                    log.notice("lane-window \(Int(size.width))x\(Int(size.height)) @\(window.backingScaleFactor)x")
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        #endif
    }

    #if os(macOS)
    static var quiet: Bool { UserDefaults.standard.bool(forKey: "lane_quiet") }

    /// 隐藏启动的窗口 canBecomeMain 为 false（只有上屏的窗口才能成主窗口），按「有标题栏、有内容」找自己的主窗口。
    @MainActor static var laneWindow: NSWindow? {
        NSApp.windows.first { $0.styleMask.contains(.titled) && $0.contentView != nil }
    }

    /// 在 applicationWillFinishLaunching 里调：赶在 SwiftUI 挂窗口之前把进程改成 accessory。
    @MainActor static func enterQuietIfAsked() {
        guard quiet else { return }
        NSApp.setActivationPolicy(.accessory)
        // SwiftUI 的窗口是后挂上来的：每轮事件循环结束扫一遍新窗口，透明、不接鼠标、不进 Mission Control、挪到屏外。
        NotificationCenter.default.addObserver(forName: NSApplication.didUpdateNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated {
                for window in NSApp.windows where window.alphaValue != 0 {
                    window.alphaValue = 0
                    window.ignoresMouseEvents = true
                    window.collectionBehavior.insert([.transient, .ignoresCycle])
                    window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
                }
            }
        }
        log.notice("lane-quiet accessory")
    }

    @MainActor static func writeSnapshotIfAsked() {
        guard quiet, let path = UserDefaults.standard.string(forKey: "lane_snapshot") else { return }
        guard let view = laneWindow?.contentView else {
            log.error("lane-snapshot failed: no window")
            return
        }
        view.layoutSubtreeIfNeeded()
        let size = view.bounds.size
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
                                         pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else {
            log.error("lane-snapshot failed: no bitmap")
            return
        }
        rep.size = size                      // 点尺寸不变、像素翻倍 = 2 倍渲染，与本机接的是几倍屏无关
        view.cacheDisplay(in: view.bounds, to: rep)
        do {
            guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: URL(fileURLWithPath: path))
            log.notice("lane-snapshot \(Int(size.width * 2))x\(Int(size.height * 2)) \(path, privacy: .public)")
        } catch {
            log.error("lane-snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif
}

#if os(macOS)
/// 平台验收车道的静默启动（-lane_quiet）挂在 willFinishLaunching：不传这个参数时什么都不做。
/// App 若已有自己的 NSApplicationDelegate，在它的 applicationWillFinishLaunching 里调 LaneSignal.enterQuietIfAsked() 即可。
final class LaneAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { LaneSignal.enterQuietIfAsked() }
    }
}
#endif
