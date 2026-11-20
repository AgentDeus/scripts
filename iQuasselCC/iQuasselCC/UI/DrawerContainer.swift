import SwiftUI

/// Android-style navigation drawers: chat list on the left, nick list on the right.
struct DrawerContainer<Content: View, Left: View, Right: View>: View {
    @Binding var leftOpen: Bool
    @Binding var rightOpen: Bool
    var rightEnabled: Bool
    @ViewBuilder var content: () -> Content
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    @State private var dragOffset: CGFloat = 0
    @Environment(\.chatTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width * 0.85, 380)
            ZStack {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Color.black
                    .opacity(scrimOpacity(width))
                    .ignoresSafeArea()
                    .allowsHitTesting(leftOpen || rightOpen)
                    .onTapGesture { close() }

                HStack(spacing: 0) {
                    left()
                        .frame(width: width)
                        .background(theme.surface.ignoresSafeArea())
                        .shadow(color: .black.opacity(leftOpen ? 0.3 : 0), radius: 8)
                        .offset(x: leftOffset(width))
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(leftOpen)

                if rightEnabled {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        right()
                            .frame(width: width)
                            .background(theme.surface.ignoresSafeArea())
                            .shadow(color: .black.opacity(rightOpen ? 0.3 : 0), radius: 8)
                            .offset(x: rightOffset(width))
                    }
                    .allowsHitTesting(rightOpen)
                }
            }
            .simultaneousGesture(dragGesture(width: width, total: geo.size.width))
            .animation(.easeOut(duration: 0.22), value: leftOpen)
            .animation(.easeOut(duration: 0.22), value: rightOpen)
        }
    }

    private func close() {
        leftOpen = false
        rightOpen = false
    }

    private func leftOffset(_ w: CGFloat) -> CGFloat {
        if leftOpen { return min(0, dragOffset) }
        return -w + max(0, dragOffset)
    }

    private func rightOffset(_ w: CGFloat) -> CGFloat {
        if rightOpen { return max(0, dragOffset) }
        return w + min(0, dragOffset)
    }

    private func scrimOpacity(_ w: CGFloat) -> Double {
        if leftOpen || rightOpen { return 0.45 * Double(1 - min(abs(dragOffset), w) / w) }
        return 0.45 * Double(min(abs(dragOffset), w) / w)
    }

    private func dragGesture(width: CGFloat, total: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { v in
                let dx = v.translation.width
                guard abs(dx) > abs(v.translation.height) else { return }
                if leftOpen && dx < 0 { dragOffset = max(dx, -width) }
                else if rightOpen && dx > 0 { dragOffset = min(dx, width) }
                else if !leftOpen && !rightOpen {
                    if v.startLocation.x < 30 && dx > 0 { dragOffset = min(dx, width) }
                    else if rightEnabled && v.startLocation.x > total - 30 && dx < 0 { dragOffset = max(dx, -width) }
                }
            }
            .onEnded { v in
                let dx = v.translation.width
                let threshold = width * 0.3
                if leftOpen && dx < -threshold { leftOpen = false }
                else if rightOpen && dx > threshold { rightOpen = false }
                else if !leftOpen && !rightOpen {
                    if v.startLocation.x < 30 && dx > threshold { leftOpen = true }
                    else if rightEnabled && v.startLocation.x > total - 30 && dx < -threshold { rightOpen = true }
                }
                withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
            }
    }
}
