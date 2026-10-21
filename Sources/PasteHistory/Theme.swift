import AppKit
import SwiftUI

// MARK: - 字号

/// 四档字号。
///
/// 改之前界面上散着 9 / 9.5 / 10 / 10.5 / 11 / 12 / 13 / 14 共八档，
/// 相邻两档差不到 1pt——差不出层级，只显得没人收拾过。
/// 四档两两至少差 2pt，扫一眼就能分出主次。
enum Scale {
    /// 元信息：时间、来源、⌘N 角标、分组标题
    static let meta: CGFloat = 11
    /// 正文：摘要、展开内容
    static let body: CGFloat = 13
    /// 输入框与空状态标题
    static let field: CGFloat = 15
    /// 配对码：要能隔着一张桌子念给另一个人听
    static let code: CGFloat = 19
}

// MARK: - 图标

/// 图标三档。图标跟着作用走，不跟着容器顺手缩放。
enum Icon {
    /// 行内标记（置顶）：不抢正文
    static let mark: CGFloat = 11
    /// 可点的图标（搜索、清除、行内按钮）：13 是能看清又不出格的一档
    static let action: CGFloat = 13
    /// 缩略图占位（34 见方）
    static let thumb: CGFloat = 15
}

// MARK: - 面板尺寸

/// 面板外框。宽度恒定；高度只在「贴着输入框放不下」时才收。
///
/// 540 是一屏十条的高度，平时就这么高。但输入框常常在屏幕中段，
/// 上下都塞不下 540 —— 以前这时会把面板夹到屏幕边上，结果必然压住输入框。
/// 所以高度是区间：放得下就 540，放不下就收到恰好塞进去，但不低于 300
/// （搜索区 + 约四行，再矮扫不动了）。
enum Panel {
    static let width: CGFloat = 520
    static let maxHeight: CGFloat = 540
    static let minHeight: CGFloat = 300
}

// MARK: - 语义色

/// 界面里所有「不是正文」的颜色。
///
/// 系统语义色在这里不够用，原因是实测对比度（WCAG 相对亮度比）：
///
/// | 颜色 | 浅色底 | 深色底 |
/// |---|---|---|
/// | `tertiaryLabelColor` | 1.73:1 | 2.48:1 |
/// | `secondaryLabelColor` | 3.44:1 | 5.88:1 |
///
/// 剪贴板面板是靠「扫」来用的，来源和时间这类元信息恰恰是扫的抓手，
/// 11pt 的灰字却连 3:1 都不到——浅色模式下基本等于没有。
/// AA 对小于 18pt 的文字要求 4.5:1，所以下面两个灰是反解出来的：
/// 白底、深色底、以及选中行那层 24% 蓝底，三种背景上都过 4.5:1。
enum Palette {
    /// 元信息灰：浅色 0.38 / 深色 0.61（实测 6.19:1 / 6.07:1，选中行上 4.5:1 / 4.5:1）
    static let meta = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 0.61, alpha: 1) : NSColor(white: 0.38, alpha: 1)
    })

    /// 警告色。系统橙当文字用是看不见的：浅色底上只有 2.2:1。
    /// 这一组在浅色底 5.6:1、深色底 8.1:1。
    static let warning = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(calibratedRed: 1.00, green: 0.70, blue: 0.25, alpha: 1)
            : NSColor(calibratedRed: 0.59, green: 0.35, blue: 0.08, alpha: 1)
    })
}

private extension NSAppearance {
    /// 只认真正的深色外观，vibrant 系的毛玻璃背景同样算深色
    var isDark: Bool {
        guard let match = bestMatch(from: [.aqua, .darkAqua]) else { return false }
        return match == .darkAqua
    }
}
