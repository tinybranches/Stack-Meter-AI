import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        HStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "sparkle")
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
                    .offset(x: 3, y: -2)
            }

            if viewModel.settings.showPercentInTray,
               let used = viewModel.selectedSnapshot?.primaryUsedPercent,
               viewModel.selectedSnapshot?.status != .authNeeded
            {
                Text("\(Int(used.rounded()))%")
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.primary)
        .onAppear {
            AIBarBootstrap.startIfNeeded(viewModel)
        }
    }

    private var statusColor: Color {
        let snapshot = viewModel.selectedSnapshot
        return StatusStyle.color(
            for: snapshot?.status ?? .loading,
            isLimited: snapshot?.isLimited == true
        )
    }
}
