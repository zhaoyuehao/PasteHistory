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

/// 面板外框：默认是黄金矩形 400×647（= 400×φ），可拖边调整、记住用户选择。
///
/// 形态对齐输入法候选窗——窄而高、贴着输入框下拉。400 宽下一行摘要约 20 个字，
/// 正是候选窗的密度；647 高约十一条。字号三档（11/13/15）不动。
///
/// 拖边范围 [340, 940] × [360, 1200]：下限是行内解剖与扫读的存活线。
/// 贴着输入框放不下时高度按可用空间收（不低于 360）；避让收缩只影响本次落位、
/// 不回写用户偏好。两条硬约束不变：绝不压住输入框本体；位置每次按光标重算。
enum Panel {
    /// 冒烟参数 `--panel-size 520,540`：临时换成指定外框对比（真机 A/B 用），不影响默认值
    static var debugSize: NSSize?

    /// 默认 400（= 400×φ 的黄金矩形宽）；用户拖边调整后记住其选择
    static var width: CGFloat { debugSize?.width ?? Settings.shared.panelWidth }
    /// 期望高度：φ 默认 647 或用户选择；贴输入框放不下时在 [minHeight, 期望] 内收
    static var maxHeight: CGFloat { debugSize?.height ?? Settings.shared.panelHeight }
    /// 可调下限：行内解剖可存活的最小宽度 + 扫读可存活的最小高度
    static let minWidth: CGFloat = 340
    static let minHeight: CGFloat = 360
}

// MARK: - 预览窗尺寸

/// 空格预览大窗：默认黄金矩形 640×400（= 8:5，Fibonacci 黄金近似对），可拖边调整
/// （会话内记住用户尺寸）；不再按内容形态换高——文本滚、图片 fit、文件列表滚。
///
/// 图文记录做递归 φ 分割：说明区 153 ≈ 400×0.382、图区 247 ≈ 153×φ、
/// 整窗 400 ≈ 153×φ²——大块套小块，自相似的黄金分割。
///
/// 落位是「就地放大」：以面板为中心同心覆盖，从面板的几何长出来——
/// 视线在哪里，预览就在哪里，绝不把视线拽到面板旁边。
enum Preview {
    static let width: CGFloat = 640
    /// 默认高：640:400 = 8:5（Fib 对，φ 的整数近似）；不随内容形态切换
    static let height: CGFloat = 400
    /// 拖边下限 400×247 ≈ 默认 ÷ φ²：缩到最小仍是黄金系尺寸
    static let minWidth: CGFloat = 400
    static let minHeight: CGFloat = 247
    /// 图文记录说明区上限 = 400×0.382（黄金分割点），图区 247 与其成 φ
    static let captionHeight: CGFloat = 153
    /// 屏幕边缘留白
    static let margin: CGFloat = Rhythm.xl
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
