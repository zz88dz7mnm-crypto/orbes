import AppKit
import SwiftUI
import OrbexCore

/// Página "Servicios" de la isla: lo último de cada integración conectada (solo lectura).
struct IntegrationsPageView: View {
    @ObservedObject private var hub = IntegrationsHub.shared
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        Group {
            if hub.summaries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                    Text("Conectá servicios en Configuración › Integraciones")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(hub.summaries) { item in
                            IntegrationRow(item: item)
                        }
                    }
                }
            }
        }
    }
}

private struct IntegrationRow: View {
    let item: IntegrationSummary
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        Button {
            if let url = item.url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(size: 9.5, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(color(for: item.severity))
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .orbexCard(cornerRadius: 10)
        }
        .buttonStyle(.plain)
        .help(item.integration.title)
    }

    private func color(for s: IntegrationSeverity) -> Color {
        switch s {
        case .info: return Color.white.opacity(0.4)
        case .success: return Color.green
        case .warning: return Color.orange
        case .error: return Color.red
        }
    }
}
