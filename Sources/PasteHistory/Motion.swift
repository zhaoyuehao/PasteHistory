import SwiftUI

// MARK: - 动效

/// 动效令牌。
///
/// 一个反直觉的结论先写在这里，免得下次又调错方向：**阻尼感不来自曲线参数，
/// 来自被驱动的量的幅度**。按阻尼谐振子模型算，`spring(response: 0.30,
/// dampingFraction: 0.86)` 和 `easeOut(duration: 0.20)` 的位移曲线几乎重合
/// （40ms 时 22% vs 31%，120ms 时都是 ~78%）。真正让人觉得「丝滑」的是行高
/// 从 44pt 撑到 130pt 那种尺寸变化——换成 24% 的底色透明度，同样的曲线也没人
/// 看得出来。所以这里只管「怎么走」，走什么由调用方负责。
///
/// 两条硬规则：
/// 1. **任何情况下都不禁用动画**。连按方向键时把弹簧压短（`selectionFast`），
///    不是关掉——关掉等于瞬移，而连续移动恰恰是最需要阻尼的时刻。
/// 2. **高亮必须是一个会移动的物体**。选中项是 per-row 属性时，切换选中实际是
///    两个独立的透明度渐变，中间没有任何东西在走，人眼对交叉淡化几乎无感。
enum Motion {
    /// 选中态与跟随滚动：dampingFraction 0.78 有约 4% 过冲，滑过头再回来
    static let selection = Animation.spring(response: 0.30, dampingFraction: 0.78)

    /// 连按：压短到 0.18。仍然有阻尼，但短到能被下一次按键打断，
    /// 不会像 0.30 那样在快速连按时堆积成迟滞
    static let selectionFast = Animation.spring(response: 0.18, dampingFraction: 0.88)

    /// 边界回弹：撞到顶/底推出去再拉回来。0.55 带回弹振荡，
    /// 阻尼比给到 0.8 以上就只是「缩回去」，没有橡皮筋的味
    static let bounce = Animation.spring(response: 0.32, dampingFraction: 0.55)

    /// 悬停：比选中快一档，不然手感发木
    static let hover = Animation.easeOut(duration: 0.12)

    /// 连按判定：间隔小于这个值就用 selectionFast
    static let repeatThreshold: TimeInterval = 0.2
}
