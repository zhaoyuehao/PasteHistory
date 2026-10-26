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

// MARK: - 间距档

/// 间距档位：Fibonacci 阶梯。相邻 Fib 数之比收敛于 φ（13/8=1.625、21/13=1.615），
/// 且落在整数 pt 上——用整数近似拿到 φ 的模度。字号四档、图标三档之后的第三块拼图：
/// 以前间距散着 2/3/5/8/10/12/14/16/18/20/22，现在统一回档，新界面有档可查。
///
/// 规则：回最近档，等距取小；行高 44 与控件高度（52/20）不进阶梯——
/// 触达常数优先于模度。圆角 8:5 也是 Fib φ 对（「黄金圆」的整数近似）。
/// 例外：QR 卡衬边 11 不是档位数，是 φ 精确点（198:320≈φ⁻¹），见 QRPairPanel 注释。
enum Rhythm {
    static let xs: CGFloat = 2
    static let s: CGFloat = 3
    static let m: CGFloat = 5
    static let l: CGFloat = 8
    static let xl: CGFloat = 13
    static let xxl: CGFloat = 21
    static let xxxl: CGFloat = 34
}

enum Preview {
    /// 原图解码的最大边长：预览窗就 640 宽，8000px 整图进内存是风扇测试
    static let maxImagePixel: CGFloat = 1600
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
