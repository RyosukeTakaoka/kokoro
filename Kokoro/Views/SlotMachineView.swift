import SwiftUI

/// スロット画面のいちばん外側。背景・筐体・操作ボタン・演出レイヤーを重ねる。
struct SlotMachineView: View {
    let game: SlotGame
    let onLeave: () -> Void
    @State private var showInfo = false
    @State private var showAchievements = false
    @State private var reelTouch = false
    @Environment(\.scenePhase) private var scenePhase

    init(game: SlotGame, onLeave: @escaping () -> Void) {
        self.game = game
        self.onLeave = onLeave
    }

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, 520)
            ZStack {
                BackgroundView(game: game)

                TimelineView(.animation) { timeline in
                    VStack(spacing: 10) {
                        TopBar(game: game, showInfo: $showInfo, showAchievements: $showAchievements,
                               onLeave: onLeave)
                        Spacer(minLength: 0)
                        CabinetView(game: game, now: timeline.date, width: width - 24)
                            .scaleEffect(game.zoom)
                            .saturation(game.desaturate ? 0.05 : 1)
                            .onTouchDown(pressed: $reelTouch) { game.tapReels() }
                        Spacer(minLength: 0)
                        ControlPanel(game: game, now: timeline.date)
                    }
                    .frame(width: width)
                    .padding(.vertical, 8)
                    .offset(shakeOffset(at: timeline.date))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // 静寂・フリーズのときに画面を暗くする
                Color.black.opacity(game.dim)
                    .ignoresSafeArea()
                    .allowsHitTesting(game.freezeActive)

                ParticleLayer(system: game.particles)
                FlashLayer(game: game)
                SlamLayer(slam: game.slam)
                    .allowsHitTesting(false)
                ToastLayer(toast: game.toast)
                    .allowsHitTesting(false)

                if game.phase == .awaitingPush {
                    PushOverlay(game: game)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: game.phase == .awaitingPush)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(isPresented: $showInfo) {
            MachineInfoView(game: game)
        }
        .sheet(isPresented: $showAchievements) {
            AchievementsView(player: game.player)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { game.appBecameActive() }
        }
    }

    /// 画面揺れ。常時の揺れ(タメ中)と、1 発ごとに減衰する揺れを足す
    private func shakeOffset(at now: Date) -> CGSize {
        var amp = game.shakeBase
        let s = game.shake
        let elapsed = now.timeIntervalSince(s.start)
        if elapsed >= 0 && elapsed < s.duration {
            let k = 1 - elapsed / s.duration
            amp += s.amplitude * k * k
        }
        guard amp > 0.05 else { return .zero }
        let t = now.timeIntervalSinceReferenceDate
        let x = sin(t * 93.1) * 0.6 + sin(t * 151.7) * 0.4
        let y = sin(t * 87.3 + 1.3) * 0.6 + sin(t * 133.9 + 0.4) * 0.4
        return CGSize(width: amp * x, height: amp * y)
    }
}

// MARK: - 上の帯(台番号・クレジット・差枚・データ)

private struct TopBar: View {
    let game: SlotGame
    @Binding var showInfo: Bool
    @Binding var showAchievements: Bool
    let onLeave: () -> Void

    var body: some View {
        let data = game.machineData
        HStack(alignment: .center, spacing: 8) {
            Button {
                game.leave()
                onLeave()
            } label: {
                VStack(spacing: 0) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                    Text("\(game.machineNumber)")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                }
                .foregroundStyle(.white.opacity(game.canLeave ? 0.85 : 0.25))
                .frame(width: 40, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.1)))
            }
            .disabled(!game.canLeave)
            .accessibilityLabel("席を立ってホールへ戻る")

            LEDCounter(label: "CREDIT", value: game.credits, color: .orange)
            LEDCounter(label: "差枚", value: game.player.netMedals,
                       color: game.player.netMedals >= 0 ? .green : .red, signed: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(data.gamesSinceBonus)G")
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                HStack(spacing: 5) {
                    Text("B\(data.bigCount)").foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
                    Text("R\(data.regCount)").foregroundStyle(Color(red: 0.45, green: 0.7, blue: 1))
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            Spacer(minLength: 0)
            iconButton("trophy.fill", label: "実績") { showAchievements = true }
            iconButton("chart.bar.fill", label: "台データと設定") { showInfo = true }
        }
        .padding(.horizontal, 12)
    }

    private func iconButton(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 36, height: 36)
                .background(Circle().fill(.white.opacity(0.1)))
        }
        .accessibilityLabel(label)
    }
}

/// 7 セグ風の数字
struct LEDCounter: View {
    let label: String
    let value: Int
    let color: Color
    var signed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
            Text(signed ? String(format: "%+ld", value) : String(format: "%04ld", value))
                .font(.system(size: 18, weight: .black, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.9), radius: 6)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy(duration: 0.12), value: value)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.35), lineWidth: 1))
    }
}
