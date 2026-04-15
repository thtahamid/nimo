import SwiftUI

struct ActionButtonsView: View {
    let isInstalled: Bool
    let canInstall: Bool
    let isBusy: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onInstall) {
                Text("Install")
                    .frame(minWidth: 80)
            }
            .disabled(!canInstall || isBusy || isInstalled)

            Button(action: onUninstall) {
                Text("Uninstall")
                    .frame(minWidth: 80)
            }
            .disabled(!isInstalled || isBusy)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()
        }
    }
}

#if DEBUG
struct ActionButtonsView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ActionButtonsView(isInstalled: false, canInstall: true, isBusy: false, onInstall: {}, onUninstall: {})
            ActionButtonsView(isInstalled: true, canInstall: true, isBusy: false, onInstall: {}, onUninstall: {})
            ActionButtonsView(isInstalled: false, canInstall: true, isBusy: true, onInstall: {}, onUninstall: {})
        }
        .padding()
    }
}
#endif
