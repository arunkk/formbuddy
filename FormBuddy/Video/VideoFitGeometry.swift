import CoreGraphics

/// Pure geometry for fitting video into a view.
///
/// Video is never cropped: it is always fit (letterboxed) inside the space
/// available, so the whole lifter — and every body-anchored highlight drawn over
/// them — stays on screen. When the natural fit would be taller than the room we
/// have, the surface is scaled down (it "zooms out") instead of pushing the
/// scrubber and play controls off screen. Interactive zoom is clamped to a sane
/// range and always resettable back to fit.
///
/// Used by the feedback player and the camera preview, and kept free of SwiftUI
/// so the fit/clamp math is unit-testable.
enum VideoFitGeometry {
    static let minZoom: CGFloat = 1
    static let maxZoom: CGFloat = 5
    /// A double-tap magnifies to this, then taps back to fit.
    static let doubleTapZoom: CGFloat = 2.5

    /// Height cap for a fitted surface inside a viewport of `viewport` points.
    /// A full-body portrait clip is naturally taller than the screen; capping it
    /// keeps the video, strip, and controls visible without scrolling. Falls back
    /// to a phone-friendly value until the viewport has been measured.
    static func maximumHeight(
        viewport: CGFloat,
        minimum: CGFloat = 320,
        maximum: CGFloat = 560
    ) -> CGFloat {
        guard viewport.isFinite, viewport > 0 else { return 460 }
        return min(max(viewport * 0.55, minimum), maximum)
    }

    /// Size of an `aspect`-ratio video that fits inside `available` without
    /// cropping — the "zoomed out" size. Returns `.zero` for degenerate input.
    static func fittedSize(aspect: CGFloat, available: CGSize) -> CGSize {
        guard aspect.isFinite, aspect > 0,
              available.width.isFinite, available.height.isFinite,
              available.width > 0, available.height > 0 else { return .zero }
        let heightLimitedWidth = available.height * aspect
        if heightLimitedWidth <= available.width {
            return CGSize(width: heightLimitedWidth, height: available.height)
        }
        return CGSize(width: available.width, height: available.width / aspect)
    }

    /// The rect of a fitted video, centered in `available`. Convenience over
    /// `fittedSize` for callers that need a position (e.g. a framing guide).
    static func fittedRect(aspect: CGFloat, available: CGSize) -> CGRect {
        let size = fittedSize(aspect: aspect, available: available)
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGRect(
            x: (available.width - size.width) / 2,
            y: (available.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Clamp a zoom factor into the supported range.
    static func clampedZoom(_ zoom: CGFloat) -> CGFloat {
        guard zoom.isFinite else { return minZoom }
        return min(max(zoom, minZoom), maxZoom)
    }

    /// Zoom to use while a pinch is in flight.
    static func effectiveZoom(base: CGFloat, pinch: CGFloat) -> CGFloat {
        clampedZoom(base * (pinch.isFinite ? pinch : 1))
    }

    /// Zoom after a double-tap: fit ⇄ a comfortable magnified level.
    static func toggledZoom(_ zoom: CGFloat) -> CGFloat {
        clampedZoom(zoom) > minZoom + 0.001 ? minZoom : clampedZoom(doubleTapZoom)
    }

    /// Whether a zoom level is meaningfully magnified (used to show the "Fit"
    /// reset affordance and reset on rep change).
    static func isMagnified(_ zoom: CGFloat) -> Bool {
        clampedZoom(zoom) > minZoom + 0.001
    }
}