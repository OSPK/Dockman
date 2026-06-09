import CoreGraphics
import ConfigKit

/// Pure, view-free geometry for classic Dock magnification: given a cursor
/// position along the bar's *length* axis and the centers of the icons, it
/// produces a per-icon scale that peaks under the cursor and falls off to 1.0
/// for neighbours outside the influence radius. Kept free of AppKit so the
/// falloff curve can be unit-tested directly (docs/07 Phase 4).
public enum Magnifier {
    /// Default peak scale directly under the cursor (user-tunable per dock).
    public static let maxScale: CGFloat = 1.6
    /// Influence radius as a multiple of the icon stride (icon + gap). Icons
    /// farther than this from the cursor stay at scale 1.0.
    public static let influenceStrides: CGFloat = 2.0

    /// Scale for an icon whose center is `distance` points from the cursor along
    /// the length axis. `stride` is the icon-to-icon spacing (icon + gap);
    /// `maxScale` the peak zoom under the cursor.
    ///
    /// A raised-cosine falloff: smooth at both the peak and the edge of the
    /// influence window, so neighbours ease in rather than stepping.
    public static func scale(distance: CGFloat, stride: CGFloat,
                             maxScale: CGFloat = Magnifier.maxScale) -> CGFloat {
        guard stride > 0, maxScale > 1 else { return 1 }
        let radius = influenceStrides * stride
        let d = abs(distance)
        if d >= radius { return 1 }
        // cos ramps 1→0 over [0, radius]; map onto [maxScale, 1].
        let t = cos((d / radius) * (.pi / 2))   // 1 at center, 0 at edge
        return 1 + (maxScale - 1) * t
    }

    /// Extra cross-axis room a magnified bar needs beyond `iconSize` so the
    /// peak icon isn't clipped by the window bounds. Zero when magnification is
    /// off.
    public static func headroom(iconSize: CGFloat, enabled: Bool,
                                maxScale: CGFloat = Magnifier.maxScale) -> CGFloat {
        guard enabled, maxScale > 1 else { return 0 }
        return iconSize * (maxScale - 1)
    }
}
