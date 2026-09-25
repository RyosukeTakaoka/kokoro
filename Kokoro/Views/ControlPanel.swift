import SwiftUI

/// 下の操作部: 停止ボタン 3 つ・レバー・オート
struct ControlPanel: View {
    let game: SlotGame
    let now: Date

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                ForEach(0..<3, id: \.self) { i in
                    StopButton(state: stopState(i), now: now) {
                        if game.nextReel == i { game.pressStop() }
                    }
                }
            }
            HStack(spacing: 14) {
                AutoToggle(isOn: game.auto) { game.auto.toggle() }
                if game.needsRefill {
                    Button {
                        game.refill()
                    } label: {
                        Text("メダルを借りる +\(SlotGame.refillAmount)")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(Capsule().fill(Color.yellow))
                    }
                } else {
                    LeverButton(enabled: game.canPullLever, free: game.freeGame, now: now) {
                        game.pullLever()
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 18)
    }

    private func stopState(_ i: Int) -> StopButton.Visual {
        guard let next = game.nextReel else { return .off }
        if i < next { return .off }
        if i > next { return .waiting }
        if i == 2, game.isLastReelReach, let hint = game.buttonHint { return .reach(hint) }
        return .ready
    }
}

private struct StopButton: View {
    enum Visual: Equatable {
        case off
        case waiting
        case ready
        case reach(ExpectColor)
    }

    let state: Visual
    let now: Date
    let action: () -> Void

    var body: some View {
        let t = now.timeIntervalSinceReferenceDate
        let pulse = 0.5 + 0.5 * sin(t * (isReach ? 14 : 7))
        TouchDownButton(enabled: state == .ready || isReach, action: action) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [fill.opacity(0.95), fill.opacity(0.45)], center: .topLeading,
                                         startRadius: 4, endRadius: 60))
                Circle()
                    .stroke(.white.opacity(state == .off ? 0.15 : 0.7), lineWidth: 3)
                Text("STOP")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(state == .off ? Color.white.opacity(0.3) : Color.white)
            }
            .frame(width: 76, height: 76)
            .shadow(color: glow.opacity(state == .ready || isReach ? 0.5 + 0.5 * pulse : 0), radius: 16)
            .scaleEffect(isReach ? 1 + 0.07 * pulse : 1)
        }
    }

    private var isReach: Bool {
        if case .reach = state { return true }
        return false
    }

    private var fill: Color {
        switch state {
        case .off: return Color(white: 0.2)
        case .waiting: return Color(red: 0.35, green: 0.1, blue: 0.1)
        case .ready: return Color(red: 0.95, green: 0.15, blue: 0.2)
        case .reach(let hint):
            if hint == .rainbow {
                let t = now.timeIntervalSinceReferenceDate
                return Color(hue: (t * 0.8).truncatingRemainder(dividingBy: 1), saturation: 0.9, brightness: 1)
            }
            return hint.color
        }
    }

    private var glow: Color {
        if case .reach = state { return fill }
        return .red
    }
}

private struct LeverButton: View {
    let enabled: Bool
    let free: Bool
    let now: Date
    let action: () -> Void

    var body: some View {
        let t = now.timeIntervalSinceReferenceDate
        TouchDownButton(enabled: enabled, action: action) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                Text(free ? "START (FREE)" : "START  -3枚")
            }
            .font(.system(size: 19, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                Capsule().fill(LinearGradient(colors: enabled
                    ? [Color(red: 1, green: 0.35, blue: 0.5), Color(red: 0.75, green: 0.05, blue: 0.3)]
                    : [Color(white: 0.3), Color(white: 0.18)],
                    startPoint: .top, endPoint: .bottom))
            )
            .overlay(Capsule().stroke(.white.opacity(enabled ? 0.8 : 0.2), lineWidth: 2))
            .shadow(color: Color(red: 1, green: 0.2, blue: 0.5).opacity(enabled ? 0.5 + 0.4 * sin(t * 4) : 0),
                    radius: 14)
        }
    }
}

private struct AutoToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("AUTO")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.8))
                .frame(width: 72, height: 64)
                .background(Capsule().fill(isOn ? Color.green : Color(white: 0.2)))
                .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(PressDownStyle())
    }
}

/// 指が触れた瞬間に反応するボタン(普通の Button は指を離したときに反応するので、目押しに向かない)
struct TouchDownButton<Label: View>: View {
    var enabled = true
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var pressed = false

    var body: some View {
        label()
            .scaleEffect(pressed ? 0.9 : 1)
            .brightness(pressed ? 0.15 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.5), value: pressed)
            .contentShape(Rectangle())
            .onTouchDown(pressed: $pressed) {
                if enabled { action() }
            }
    }
}

extension View {
    /// 触れた瞬間に 1 回だけ呼ぶ。`pressed` は指が触れている間 true
    func onTouchDown(pressed: Binding<Bool>, perform action: @escaping () -> Void) -> some View {
        gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed.wrappedValue else { return }
                    pressed.wrappedValue = true
                    action()
                }
                .onEnded { _ in pressed.wrappedValue = false }
        )
    }
}

/// 押した瞬間にへこむボタン
struct PressDownStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .brightness(configuration.isPressed ? 0.15 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.5), value: configuration.isPressed)
    }
}
