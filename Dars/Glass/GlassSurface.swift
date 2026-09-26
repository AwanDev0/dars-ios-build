import SwiftUI

struct GlassSurface<Content: View>: View {
    var radius: CGFloat = Metrics.Radius.lg
    var rimmed: Bool = true
    var tint: Color?
    var interactive: Bool = false
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    var body: some View {
        if reduceTransparency {
            content
                .background(shape.fill(DarsColor.surface))
                .overlay(shape.strokeBorder(DarsColor.separator, lineWidth: 0.5))
                .clipShape(shape)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(liquid, in: shape)
        } else {
            legacy
        }
    }

    @available(iOS 26.0, *)
    private var liquid: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    private var legacy: some View {
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(DarsColor.glassTint))
            }
            .overlay {
                if rimmed {
                    shape.strokeBorder(DarsColor.glassStroke, lineWidth: 0.5)
                }
            }
            .clipShape(shape)
    }
}

struct DarsCard<Content: View>: View {
    var radius: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(DarsColor.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DarsColor.separator, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
