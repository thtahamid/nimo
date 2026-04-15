import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = InstallerViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeaderView()
            DiscordStatusView(installations: viewModel.installations)
            ModeSelectionView()
            ActionButtonsView(
                isInstalled: viewModel.isAnyInstalled,
                canInstall: viewModel.canInstall,
                isBusy: viewModel.isBusy,
                onInstall: { viewModel.install() },
                onUninstall: { viewModel.uninstall() }
            )
            StatusMessageView(
                message: viewModel.statusMessage,
                isError: viewModel.isErrorMessage
            )
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.refresh()
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
