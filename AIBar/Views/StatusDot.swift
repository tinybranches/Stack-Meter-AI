import SwiftUI

enum StatusStyle {
    /// Green = authorized/OK, orange = needs auth, red = limits hit.
    static func color(for status: SessionStatus, isLimited: Bool = false) -> Color {
        if isLimited || status == .rateLimited { return .red }
        switch status {
        case .active: return .green
        case .authNeeded: return .orange
        case .rateLimited: return .red
        case .unavailable, .loading: return .secondary
        }
    }
}

struct StatusDot: View {
    let status: SessionStatus
    var isLimited: Bool = false
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(StatusStyle.color(for: status, isLimited: isLimited))
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .accessibilityLabel(status.title)
    }
}
