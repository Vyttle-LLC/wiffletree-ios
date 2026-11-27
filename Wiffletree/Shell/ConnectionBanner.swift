import SwiftUI
import WiffletreeDesignSystem

/// A thin line atop a screen whose actions need the host, shown while the host is not
/// connected, so a tap that cannot reach it is never a surprise.
struct ConnectionBanner: View {
    let host: LiveHost

    var body: some View {
        if let notice = host.connectionNotice {
            HStack(spacing: 6) {
                if notice.isRetrying {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "wifi.slash")
                }
                Text(notice.text)
            }
            .font(.footnote)
            .foregroundStyle(Tidal.subtle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Tidal.overlay)
            .accessibilityElement(children: .combine)
        }
    }
}
