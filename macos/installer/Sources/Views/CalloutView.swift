import SwiftUI

struct CalloutView: View {
    let kind: CalloutKind
    let title: String
    let detail: String?
    let action: CalloutAction?

    init(kind: CalloutKind, title: String, detail: String? = nil, action: CalloutAction? = nil) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(kind.tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let action = action {
                    Button(action.title) {
                        NSWorkspace.shared.open(action.url)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(kind.tint)
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(kind.tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(kind.tint.opacity(0.35), lineWidth: 1)
        )
    }
}

#if DEBUG
struct CalloutView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 8) {
            CalloutView(kind: .info, title: "Informational note")
            CalloutView(kind: .success, title: "Installation complete.", detail: "Nimo active on Discord Stable.")
            CalloutView(kind: .warning, title: "Discord not detected", detail: "Install Discord from discord.com first.")
            CalloutView(
                kind: .error,
                title: "macOS blocked the install",
                detail: "Enable Nimo in App Management and retry.",
                action: CalloutAction(title: "Open System Settings", url: URL(string: "https://example.com")!)
            )
        }
        .padding()
        .frame(width: 520)
    }
}
#endif
