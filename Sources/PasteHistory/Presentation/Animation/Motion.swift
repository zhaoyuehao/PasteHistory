import AppKit
import SwiftUI

// MARK: - 动效

/// 动效令牌。
///
/// 动效要有可辨认的运动，并保持位置与速度连续。时长取决于移动距离、
/// 尺寸变化与使用频率，不能单靠延长时间获得阻尼感。高频预览采用克制的
/// 位移和落稳，不用额外回弹来表现“弹簧”；中途输入直接改变当前目标。
///
/// 三条硬规则：
/// 1. **任何情况下都不禁用动画**。连按方向键时把弹簧压短（`selectionFast`），
///    不是关掉——关掉等于瞬移，而连续移动恰恰最需要阻尼。
/// 2. **高亮必须是一个会移动的物体**。选中项是 per-row 属性时，切换选中实际是
///    两个独立的透明度渐变，中间没有任何东西在走，人眼对交叉淡化几乎无感。
/// 3. **系统开启「减少动态效果」时降级为短淡入淡出，不是关掉**（规范 5.5）——
///    降级不等于静止。
enum Motion {
    /// 系统辅助功能开了「减少动态效果」吗。运动类动效（弹簧、位移、缩放）
    /// 全部换成短淡入淡出；淡入淡出本身不受影响
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static let paperOpenDuration: TimeInterval = 0.24
    // Both directions use the same path, duration and symmetric timing curve.
    static let paperCloseDuration = paperOpenDuration
    // Triple real pole: retargeting preserves position, velocity AND acceleration.
    // Independent of remaining distance; no compressed 80 ms return trajectory.
    static let paperRetargetFrequency: CGFloat = 64
    static let paperFollowFrequency: CGFloat = 46
    static let paperFollowDamping: CGFloat = 0.86
    static let paperScaleReturnDuration: TimeInterval = 0.15

    /// Monotone settle: a clear acceleration followed by a long deceleration,
    /// with zero endpoint velocity/acceleration rather than an ornamental bounce.
    static func paperProgress(_ fraction: CGFloat, opening: Bool) -> CGFloat {
        SettlingTrack.progress(fraction)
    }

    /// 选中态与跟随滚动：dampingFraction 0.78 有约 4% 过冲，滑过头再回来
    static var selection: Animation {
        reduceMotion ? .easeOut(duration: 0.18)
                     : .spring(response: 0.30, dampingFraction: 0.78)
    }

    /// 连按：压短到 0.18。仍然有阻尼，但短到能被下一次按键打断，
    /// 不会像 0.30 那样在快速连按时堆积成迟滞
    static var selectionFast: Animation {
        reduceMotion ? .easeOut(duration: 0.12)
                     : .spring(response: 0.18, dampingFraction: 0.88)
    }

    /// 边界回弹：撞到顶/底推出去再拉回来。0.55 带回弹振荡，
    /// 阻尼比给到 0.8 以上就只是「缩回去」，没有橡皮筋的味
    static var bounce: Animation {
        reduceMotion ? .easeOut(duration: 0.15)
                     : .spring(response: 0.32, dampingFraction: 0.55)
    }

    /// 悬停：比选中快一档，不然手感发木（纯淡入淡出，无需降级）
    static let hover = Animation.easeOut(duration: 0.12)

    /// 撞墙位移：列表与预览大窗共用。8pt 够看见、又不至于糊成一片
    static let bounceDistance: CGFloat = 8

    /// 连按判定：间隔小于这个值就用 selectionFast
    static let repeatThreshold: TimeInterval = 0.2
}
