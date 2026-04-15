import SwiftUI

struct DiscordStatusView: View {
    let installations: [DiscordInstallation]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if installations.isEmpty {
                Text("Discord not detected")
                    .foregroundColor(.red)
                    .font(.body)
            } else {
                ForEach(installations) { installation in
                    row(for: installation)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(for installation: DiscordInstallation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(installation.edition.displayName)
                .font(.body)
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(installation.appURL.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

#if DEBUG
struct DiscordStatusView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DiscordStatusView(installations: [])
            DiscordStatusView(installations: [
                DiscordInstallation(
                    edition: .stable,
                    appURL: URL(fileURLWithPath: "/Applications/Discord.app"),
                    isInstalled: false
                )
            ])
        }
        .padding()
    }
}
#endif
