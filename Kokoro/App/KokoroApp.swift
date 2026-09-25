import SwiftUI

@main
struct KokoroApp: App {
    var body: some Scene {
        WindowGroup {
            SlotMachineView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}
