import SwiftUI

@main
struct KokoroApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}

/// ホール(台選び) ⇄ スロット台 の切り替え
struct RootView: View {
    @State private var player = PlayerStore()
    @State private var hall = HallStore()
    @State private var game: SlotGame?

    var body: some View {
        ZStack {
            if let game {
                SlotMachineView(game: game) {
                    withAnimation(.easeInOut(duration: 0.35)) { self.game = nil }
                }
                .transition(.move(edge: .trailing))
            } else {
                HallView(player: player, hall: hall) { number in
                    withAnimation(.easeInOut(duration: 0.35)) {
                        game = SlotGame(machineNumber: number, player: player, hall: hall)
                    }
                }
                .transition(.move(edge: .leading))
            }
        }
    }
}
