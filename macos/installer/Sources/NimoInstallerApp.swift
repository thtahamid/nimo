import SwiftUI

@main
struct NimoInstallerApp: App {
    var body: some Scene {
        windowGroup
    }

    @SceneBuilder
    private var windowGroup: some Scene {
        if #available(macOS 13.0, *) {
            WindowGroup("Nimo Installer") {
                ContentView()
                    .frame(width: 480, height: 360)
            }
            .windowResizability(.contentSize)
        } else {
            WindowGroup("Nimo Installer") {
                ContentView()
                    .frame(width: 480, height: 360)
            }
        }
    }
}
