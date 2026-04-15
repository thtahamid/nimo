import SwiftUI

@main
struct NimoInstallerApp: App {
    var body: some Scene {
        WindowGroup("Nimo Installer") {
            ContentView()
                .frame(minWidth: 560, idealWidth: 580, maxWidth: 720,
                       minHeight: 480, idealHeight: 520, maxHeight: 900)
        }
    }
}
