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

// MARK: - 面板尺寸

/// 面板外框是一个黄金矩形：400 × 647（= 400 × φ）。
///
/// 形态对齐输入法候选窗——窄而高、贴着输入框下拉，这本来就是面板的自我定位
/// （见 place() 的落位策略）。400 宽下一行摘要约 20 个字，正是候选窗的密度；
/// 647 高比旧框（520×540）还多放一条。字号三档（11/13/15）不用动——
/// 现有字号恰好落在这个密度上。
///
/// 收缩区间 [400, 647] 两端也成 φ（647 ÷ 400 = 1.618）：贴着输入框放不下时
/// 高度在区间内收，收到底仍有约七行半可扫。两条硬约束不变：绝不压住输入框
/// 本体（下方塞不下优先翻上方，不再往 400 以下硬塞）；位置每次按光标重算。
enum Panel {
    /// 冒烟参数 `--panel-size 520,540`：临时换成指定外框对比（真机 A/B 用），不影响默认值
    static var debugSize: NSSize?

    static var width: CGFloat { debugSize?.width ?? 400 }
    /// 放得下时的高度 = 宽 × φ，也是收缩区间的上限
    static var maxHeight: CGFloat { debugSize?.height ?? 647 }
    /// 收缩下限 = 宽度本身（黄金区间的另一端）；冒烟对比时用旧下限 300 复现老行为
    static var minHeight: CGFloat { debugSize == nil ? 400 : 300 }
}

// MARK: - 预览窗尺寸

/// 空格预览大窗。宽度恒定；高度按内容形态给，塞不下收到恰好放得下。
///
/// 落位是「就地放大」：以面板为中心同心覆盖，从面板的几何长出来——
/// 视线在哪里，预览就在哪里，绝不把视线拽到面板旁边。
enum Preview {
    static let width: CGFloat = 640
    static let textHeight: CGFloat = 520
    static let imageHeight: CGFloat = 460
    static let filesHeight: CGFloat = 440
    static let minHeight: CGFloat = 300
    /// 屏幕边缘留白
    static let margin: CGFloat = 12
    /// 切换条目时新内容浮入的位移：有东西在移动，才谈得上阻尼感
    static let slideDistance: CGFloat = 16
    /// 原图解码的最大边长：预览窗就 640 宽，8000px 整图进内存是风扇测试
    static let maxImagePixel: CGFloat = 1600
    /// 超长文本只渲染前 N 字符，底部亮截断提示
    static let maxTextLength: Int = 100_000
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
