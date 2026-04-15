import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = InstallerViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeaderView()

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Detected installations")
                DiscordStatusView(installations: viewModel.installations)
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Mode")
                ModeSelectionView()
            }

            ActionButtonsView(
                isInstalled: viewModel.isAnyInstalled,
                canInstall: viewModel.canInstall,
                isBusy: viewModel.isBusy,
                onInstall: { viewModel.install() },
                onUninstall: { viewModel.uninstall() }
            )

            StatusMessageView(callout: viewModel.statusCallout)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.refresh()
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 580, height: 520)
    }
}
#endif
