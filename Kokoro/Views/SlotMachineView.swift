import SwiftUI

/// スロット画面のいちばん外側。背景・筐体・操作ボタン・演出レイヤーを重ねる。
struct SlotMachineView: View {
    @State private var game = SlotGame()
    @State private var showSettings = false
    @State private var reelTouch = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, 520)
            ZStack {
                BackgroundView(game: game)

                TimelineView(.animation) { timeline in
                    VStack(spacing: 10) {
                        TopBar(game: game, showSettings: $showSettings)
                        Spacer(minLength: 0)
                        CabinetView(game: game, now: timeline.date, width: width - 24)
                            .scaleEffect(game.zoom)
                            .saturation(game.desaturate ? 0.05 : 1)
                            .onTouchDown(pressed: $reelTouch) { handleReelTap() }
                        Spacer(minLength: 0)
                        ControlPanel(game: game, now: timeline.date)
                    }
                    .frame(width: width)
                    .padding(.vertical, 8)
                    .offset(shakeOffset(at: timeline.date))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // 静寂のときに画面を暗くする
                Color.black.opacity(game.dim)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                ParticleLayer(system: game.particles)
                FlashLayer(game: game)
                SlamLayer(slam: game.slam)
                    .allowsHitTesting(false)

                if game.phase == .awaitingPush {
                    PushOverlay(game: game)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: game.phase == .awaitingPush)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(isPresented: $showSettings) {
            SettingsView(game: game)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { game.appBecameActive() }
        }
    }

    /// リールの上をタップ: 止まっていればレバー、回っていれば次のリールを止める
    private func handleReelTap() {
        switch game.phase {
        case .idle: game.pullLever()
        case .spinning: game.pressStop()
        case .awaitingPush: game.tapPush()
        case .buildUp, .presenting: break
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

// MARK: - 上の帯(クレジット・差枚・データ)

private struct TopBar: View {
    let game: SlotGame
    @Binding var showSettings: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            LEDCounter(label: "CREDIT", value: game.credits, color: .orange)
            LEDCounter(label: "差枚", value: game.netMedals, color: game.netMedals >= 0 ? .green : .red,
                       signed: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(game.gamesSinceBonus)G")
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Text("BIG \(game.bigCount)").foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
                    Text("REG \(game.regCount)").foregroundStyle(Color(red: 0.45, green: 0.7, blue: 1))
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            Spacer(minLength: 0)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white.opacity(0.1)))
            }
            .accessibilityLabel("設定とデータ")
        }
        .padding(.horizontal, 14)
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
                .font(.system(size: 20, weight: .black, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.9), radius: 6)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy(duration: 0.12), value: value)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.35), lineWidth: 1))
    }
}
