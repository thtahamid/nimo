import SwiftUI

struct DiscordStatusView: View {
    let installations: [DiscordInstallation]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if installations.isEmpty {
                CalloutView(
                    kind: .warning,
                    title: "Discord not detected",
                    detail: "Install Discord from discord.com, then relaunch Nimo."
                )
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
        if installation.isInstalled {
            CalloutView(
                kind: .success,
                title: "Nimo wrapper ready for \(installation.edition.displayName)",
                detail: "Launch “\(installation.edition.displayName) (Nimo)” from ~/Applications to run Discord through Nimo."
            )
        } else {
            CalloutView(
                kind: .info,
                title: installation.edition.displayName,
                detail: installation.appURL.path
            )
        }
    }
}

#if DEBUG
struct DiscordStatusView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 8) {
            DiscordStatusView(installations: [])
            DiscordStatusView(installations: [
                DiscordInstallation(
                    edition: .stable,
                    appURL: URL(fileURLWithPath: "/Applications/Discord.app"),
                    isInstalled: false
                ),
                DiscordInstallation(
                    edition: .canary,
                    appURL: URL(fileURLWithPath: "/Applications/Discord Canary.app"),
                    isInstalled: true
                )
            ])
        }
        .padding()
        .frame(width: 520)
    }
}
#endif
