import SwiftUI

// MARK: - 背景

/// 状態に合わせて色と動きが変わる背景。
/// 通常 = 紫の揺らめき / リーチ = 赤い脈動 / タメ = 期待度の色 / ボーナス = 虹が回る / RUSH = ピンクの閃光
struct BackgroundView: View {
    let game: SlotGame

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Color(red: 0.03, green: 0.01, blue: 0.08)
                base(t: t)
                if let aura = game.aura {
                    let progress = game.buildUpProgress(at: timeline.date)
                    RadialGradient(colors: [aura.color.opacity(0.35 + 0.45 * progress), .clear],
                                   center: .center, startRadius: 10, endRadius: 520)
                        .blendMode(.plusLighter)
                        .scaleEffect(1 + 0.08 * sin(t * (6 + 20 * progress)))
                }
                if game.rays {
                    RaysView(phase: t, count: 18, colorful: true)
                        .opacity(0.55)
                        .blendMode(.plusLighter)
                }
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func base(t: Double) -> some View {
        switch game.mood {
        case .normal:
            ZStack {
                blob(Color(red: 0.45, green: 0.1, blue: 0.7), x: 0.2 + 0.1 * sin(t * 0.3), y: 0.25, r: 380)
                blob(Color(red: 0.9, green: 0.15, blue: 0.5), x: 0.85, y: 0.75 + 0.08 * cos(t * 0.4), r: 340)
                blob(Color(red: 0.1, green: 0.2, blue: 0.8), x: 0.5 + 0.2 * cos(t * 0.21), y: 0.55, r: 300)
            }
            .opacity(0.55)
        case .reach:
            // 心臓の鼓動に合わせた赤い脈動
            let beat = pow(max(0, sin(t * 2 * .pi * 1.6)), 8)
            ZStack {
                Color(red: 0.25 + 0.3 * beat, green: 0, blue: 0.02)
                RadialGradient(colors: [Color.red.opacity(0.2 + 0.5 * beat), .clear], center: .center,
                               startRadius: 0, endRadius: 500)
            }
        case .bonus:
            ZStack {
                RainbowFill.angular(phase: t * 0.15)
                    .rotationEffect(.degrees(t * 25))
                    .scaleEffect(2.2)
                    .opacity(0.45)
                Color.black.opacity(0.35)
                RaysView(phase: t, count: 12, colorful: false)
                    .opacity(0.25)
                    .blendMode(.plusLighter)
            }
        case .rush:
            let strobe = pow(max(0, sin(t * 2 * .pi * 2.5)), 6)
            ZStack {
                LinearGradient(colors: [Color(red: 0.5, green: 0, blue: 0.4), Color(red: 0.1, green: 0, blue: 0.3)],
                               startPoint: .top, endPoint: .bottom)
                RaysView(phase: t * 1.8, count: 16, colorful: false)
                    .opacity(0.2 + 0.25 * strobe)
                    .blendMode(.plusLighter)
            }
        case .superRush:
            // 上位 RUSH: 虹の光線が速く回り、白い閃光が走る
            let strobe = pow(max(0, sin(t * 2 * .pi * 3.2)), 10)
            ZStack {
                LinearGradient(colors: [Color(red: 0.25, green: 0, blue: 0.35), Color(red: 0.02, green: 0, blue: 0.12)],
                               startPoint: .top, endPoint: .bottom)
                RaysView(phase: t * 3, count: 20, colorful: true)
                    .opacity(0.35 + 0.3 * strobe)
                    .blendMode(.plusLighter)
                Color.white.opacity(0.12 * strobe)
            }
        case .zone:
            let pulse = 0.5 + 0.5 * sin(t * 3)
            ZStack {
                LinearGradient(colors: [Color(red: 0.35, green: 0.18, blue: 0), Color(red: 0.08, green: 0.02, blue: 0)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color.orange.opacity(0.15 + 0.15 * pulse), .clear], center: .center,
                               startRadius: 0, endRadius: 480)
            }
        case .freeze:
            Color.black
        }
    }

    private func blob(_ color: Color, x: Double, y: Double, r: Double) -> some View {
        GeometryReader { geo in
            RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: r)
                .frame(width: r * 2, height: r * 2)
                .position(x: geo.size.width * x, y: geo.size.height * y)
        }
    }
}

/// 中心から放射状に回る光線
struct RaysView: View {
    let phase: Double
    let count: Int
    let colorful: Bool

    var body: some View {
        GeometryReader { geo in
            let size = max(geo.size.width, geo.size.height) * 1.6
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    let angle = Double(i) / Double(count) * 360 + phase * 30
                    RayWedge(width: 360 / Double(count) * 0.45)
                        .fill(colorful
                              ? Color(hue: (Double(i) / Double(count) + phase * 0.2).truncatingRemainder(dividingBy: 1),
                                      saturation: 0.8, brightness: 1)
                              : Color.white)
                        .rotationEffect(.degrees(angle))
                }
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
        }
    }
}

/// 中心から外へ広がる扇形 1 枚
struct RayWedge: Shape {
    let width: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        p.move(to: c)
        p.addArc(center: c, radius: r, startAngle: .degrees(-90 - width / 2), endAngle: .degrees(-90 + width / 2),
                 clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - 粒子

struct ParticleLayer: View {
    let system: ParticleSystem

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                system.update(now: timeline.date, size: size)
                system.draw(in: context)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - 画面フラッシュ

struct FlashLayer: View {
    let game: SlotGame

    var body: some View {
        fill
            .ignoresSafeArea()
            .keyframeAnimator(initialValue: 0.0, trigger: game.flashID) { content, v in
                content.opacity(v)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(game.flashStrength, duration: 0.03)
                    CubicKeyframe(game.flashStrength * 0.35, duration: 0.12)
                    CubicKeyframe(0, duration: 0.35)
                }
            }
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var fill: some View {
        switch game.flashStyle {
        case .white:
            Color.white
        case .color(let c):
            c.color.blendMode(.plusLighter)
        case .rainbow:
            RainbowFill.gradient(phase: Double(game.flashID) * 0.13).blendMode(.plusLighter)
        }
    }
}

// MARK: - 大きな文字

struct SlamLayer: View {
    let slam: SlamText?

    struct Values {
        var scale = 2.8
        var opacity = 0.0
        var blur = 14.0
        var tilt = -8.0
    }

    var body: some View {
        // 最初の 1 回もアニメーションさせるため、中身が無いときも空の文字を置いておき、id の変化で動かす
        let slam = self.slam ?? SlamText(id: 0, title: "", subtitle: nil, style: .info, hold: 0)
        ZStack {
            SlamContent(slam: slam)
                .keyframeAnimator(initialValue: Values(), trigger: slam.id) { content, v in
                    content
                        .scaleEffect(v.scale)
                        .rotationEffect(.degrees(v.tilt))
                        .blur(radius: v.blur)
                        .opacity(v.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        SpringKeyframe(0.94, duration: 0.18, spring: .snappy)
                        CubicKeyframe(1.0, duration: 0.1)
                        LinearKeyframe(1.05, duration: slam.hold)
                        CubicKeyframe(1.35, duration: 0.25)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(1, duration: 0.06)
                        LinearKeyframe(1, duration: 0.22 + slam.hold)
                        LinearKeyframe(0, duration: 0.25)
                    }
                    KeyframeTrack(\.blur) {
                        LinearKeyframe(0, duration: 0.14)
                        LinearKeyframe(0, duration: 0.14 + slam.hold)
                        LinearKeyframe(10, duration: 0.25)
                    }
                    KeyframeTrack(\.tilt) {
                        SpringKeyframe(0, duration: 0.3, spring: .bouncy)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -40)
    }
}

private struct SlamContent: View {
    let slam: SlamText

    var body: some View {
        VStack(spacing: 6) {
            title
            if let subtitle = slam.subtitle {
                Text(subtitle)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 0, x: 2, y: 2)
                    .shadow(color: .black.opacity(0.6), radius: 8)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var title: some View {
        switch slam.style {
        case .reach:
            ChromaticText(text: slam.title, size: 76, fill: AnyShapeStyle(
                LinearGradient(colors: [.white, Color(red: 1, green: 0.2, blue: 0.2)], startPoint: .top,
                               endPoint: .bottom)))
        case .yokoku(let level):
            let color = ExpectColor(rawValue: level) ?? .blue
            ChromaticText(text: slam.title, size: level >= 3 ? 60 : 48,
                          fill: color == .rainbow ? AnyShapeStyle(RainbowFill.gradient(phase: 0))
                                                  : AnyShapeStyle(color.color))
        case .bonus:
            ChromaticText(text: slam.title, size: 54, fill: AnyShapeStyle(RainbowFill.gradient(phase: 0)))
        case .push:
            ChromaticText(text: slam.title, size: 70, fill: AnyShapeStyle(
                LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)))
        case .info:
            Text(slam.title)
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 0, x: 3, y: 3)
                .shadow(color: .white.opacity(0.4), radius: 12)
        }
    }
}

/// 赤と水色を少しずらして重ねた「色ズレ」文字 + 黒縁
private struct ChromaticText: View {
    let text: String
    let size: CGFloat
    let fill: AnyShapeStyle

    var body: some View {
        let font = Font.system(size: size, weight: .black, design: .rounded).italic()
        ZStack {
            Text(text).font(font).foregroundStyle(Color.cyan.opacity(0.8)).offset(x: -4, y: 1)
            Text(text).font(font).foregroundStyle(Color.red.opacity(0.8)).offset(x: 4, y: -1)
            Text(text).font(font).foregroundStyle(.black).offset(x: 3, y: 4)
            Text(text).font(font).foregroundStyle(fill)
        }
        .minimumScaleFactor(0.4)
        .lineLimit(1)
        .shadow(color: .white.opacity(0.5), radius: 16)
    }
}

// MARK: - 実績解除のお知らせ

struct ToastLayer: View {
    let toast: AchievementToast?

    var body: some View {
        // SlamLayer と同じく、常に置いておいて id の変化でアニメーションさせる
        let achievement = toast?.achievement ?? .spins1000
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                VStack(alignment: .leading, spacing: 1) {
                    Text("実績解除: \(achievement.title)")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                    if let reward = achievement.rewardText {
                        Text("\(reward) が使えるようになりました")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.yellow)
                    } else {
                        Text(achievement.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.7), lineWidth: 1.5))
            .padding(.horizontal, 16)
            .keyframeAnimator(initialValue: -160.0, trigger: toast?.id ?? 0) { content, y in
                content.offset(y: y)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(8, duration: 0.45, spring: .bouncy)
                    LinearKeyframe(8, duration: 2.8)
                    CubicKeyframe(-160, duration: 0.35)
                }
            }
            Spacer()
        }
        .padding(.top, 4)
    }
}

// MARK: - PUSH / 連打

struct PushOverlay: View {
    let game: SlotGame

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let renda = game.pushStyle == .renda
            let progress = renda ? Double(game.rendaCount) / Double(game.rendaTarget) : 0
            let color = game.aura?.color ?? .red
            ZStack {
                Color.black.opacity(0.001) // どこをタップしても押せるように
                VStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.3))
                            .frame(width: 230, height: 230)
                            .scaleEffect(1 + 0.12 * sin(t * 12))
                            .blur(radius: 18)
                        if renda {
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(RainbowFill.angular(phase: t * 0.5),
                                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 196, height: 196)
                                .animation(.spring(response: 0.15, dampingFraction: 0.6), value: progress)
                        }
                        Circle()
                            .fill(RadialGradient(colors: [.white, color, color.opacity(0.6)], center: .topLeading,
                                                 startRadius: 4, endRadius: 170))
                            .frame(width: 170, height: 170)
                            .overlay(Circle().stroke(.white, lineWidth: 5))
                            .shadow(color: color, radius: 24)
                            .scaleEffect(1 + (renda ? 0.05 : 0.08) * sin(t * (renda ? 22 : 10)))
                        Text(renda ? "連打!!" : "PUSH!")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .italic()
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 0, x: 3, y: 3)
                    }
                    .padding(.bottom, 60)
                }
            }
        }
        .ignoresSafeArea()
        .onTouchDownRepeating { game.tapPush() }
    }
}

extension View {
    /// 触れるたびに 1 回呼ぶ(連打用)
    func onTouchDownRepeating(perform action: @escaping () -> Void) -> some View {
        modifier(TouchDownRepeating(action: action))
    }
}

private struct TouchDownRepeating: ViewModifier {
    let action: () -> Void
    @State private var down = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTouchDown(pressed: $down, perform: action)
    }
}
