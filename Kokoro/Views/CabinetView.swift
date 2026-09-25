import SwiftUI

/// 筐体: 上パネル(ロゴ/ボーナス情報)・リール窓・告知ランプ・払い出し表示
struct CabinetView: View {
    let game: SlotGame
    let now: Date
    let width: CGFloat

    var body: some View {
        let reelWidth = (width - 48) / 3
        VStack(spacing: 10) {
            TopPanel(game: game, now: now)
            ReelWindow(game: game, now: now, reelWidth: reelWidth)
            ExpectGauge(color: game.aura, progress: game.buildUpProgress(at: now), now: now,
                        canSkip: game.canSkipBuildUp)
            HStack(alignment: .center) {
                KokoroLamp(lit: game.lampLit || game.lampFlicker, now: now)
                Spacer()
                PayoutDisplay(payout: game.lastPayout, freeGame: game.freeGame)
            }
            .padding(.horizontal, 6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(LinearGradient(colors: theme.bodyColors, startPoint: .top, endPoint: .bottom))
        )
        .overlay(ChaseLights(mood: game.mood, theme: theme, now: now).padding(3))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05), .white.opacity(0.3)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
        )
        .shadow(color: moodGlow.opacity(0.6), radius: 24)
        .frame(width: width)
    }

    private var theme: CabinetTheme { game.player.theme }

    private var moodGlow: Color {
        if let aura = game.aura { return aura.color }
        switch game.mood {
        case .normal: return theme.chase.opacity(0.7)
        case .zone: return .orange
        case .reach: return .red
        case .bonus: return .yellow
        case .rush: return Color(red: 1, green: 0.2, blue: 0.8)
        case .superRush: return .white
        case .freeze: return .clear
        }
    }
}

// MARK: - 上パネル

private struct TopPanel: View {
    let game: SlotGame
    let now: Date

    var body: some View {
        let t = now.timeIntervalSinceReferenceDate
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.65))
            switch game.mode {
            case .normal:
                if game.zoneGamesLeft > 0 {
                    VStack(spacing: 2) {
                        Text("CHANCE ZONE")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .italic()
                            .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .leading,
                                                            endPoint: .trailing))
                            .scaleEffect(1 + 0.03 * sin(t * 6))
                        Text("残り \(game.zoneGamesLeft)G   ボーナス確率 2 倍")
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                } else {
                    Text("KOKORO")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .italic()
                        .tracking(6)
                        .foregroundStyle(LinearGradient(colors: game.player.theme.logo,
                                                        startPoint: .leading, endPoint: .trailing))
                        .shadow(color: game.player.theme.chase.opacity(0.5 + 0.4 * sin(t * 2.2)), radius: 10)
                }
            case .bonus(let kind, let left):
                VStack(spacing: 2) {
                    Text(kind.title)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .italic()
                        .foregroundStyle(RainbowFill.gradient(phase: t * 0.4))
                    Text("残り \(left)G   獲得 \(game.bonusGained)枚")
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
            case .rush(let left, let isSuper):
                VStack(spacing: 2) {
                    Group {
                        if isSuper {
                            Text("SUPER KOKORO RUSH")
                                .foregroundStyle(RainbowFill.gradient(phase: t * 0.8))
                        } else {
                            Text("KOKORO RUSH")
                                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.3, blue: 0.8), .yellow],
                                                                startPoint: .leading, endPoint: .trailing))
                        }
                    }
                    .font(.system(size: isSuper ? 20 : 24, weight: .black, design: .rounded))
                    .italic()
                    .scaleEffect(1 + 0.04 * sin(t * (isSuper ? 12 : 8)))
                    Text(rushLine(left: left))
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }
        }
        .frame(height: 64)
    }

    private func rushLine(left: Int) -> String {
        var line = "残り \(left)G  \(game.rushChain)連中  +\(game.rushTotal)枚"
        if let n = game.chainsToSuper {
            line += n <= 1 ? "  あと1連でSUPER!" : "  SUPERまで\(n)連"
        }
        return line
    }
}

// MARK: - リール窓

private struct ReelWindow: View {
    let game: SlotGame
    let now: Date
    let reelWidth: CGFloat

    var body: some View {
        let rowHeight = reelWidth * 0.78
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                ReelColumn(reelIndex: i, motion: game.reels[i], now: now, width: reelWidth, rowHeight: rowHeight,
                           glow: glowColor(for: i))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black))
        .overlay(PaylineView(glowID: game.paylineGlowID, reach: game.reachActive))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(LinearGradient(colors: [Color(white: 0.7), Color(white: 0.25)], startPoint: .top,
                                       endPoint: .bottom), lineWidth: 4)
        )
    }

    private func glowColor(for i: Int) -> Color? {
        if i == 2, let aura = game.aura, game.phase == .buildUp || game.phase == .awaitingPush {
            return aura.color
        }
        if i < 2 && game.reachActive { return .red }
        if game.mood == .bonus { return .yellow }
        if game.mood == .superRush { return .white }
        return nil
    }
}

private struct ReelColumn: View {
    let reelIndex: Int
    let motion: ReelMotion
    let now: Date
    let width: CGFloat
    let rowHeight: CGFloat
    let glow: Color?

    var body: some View {
        let p = motion.position(at: now)
        let speed = motion.speed(at: now)
        let base = Int(floor(p))
        let stretch = 1 + min(0.3, speed / 100)
        ZStack {
            LinearGradient(colors: [Color(red: 0.93, green: 0.9, blue: 0.84), .white,
                                    Color(red: 0.93, green: 0.9, blue: 0.84)],
                           startPoint: .top, endPoint: .bottom)
            ForEach((base - 2)...(base + 3), id: \.self) { index in
                SymbolView(symbol: motion.symbol(reel: reelIndex, index: index), size: rowHeight)
                    .frame(width: width, height: rowHeight)
                    .scaleEffect(x: 1, y: stretch)
                    .offset(y: CGFloat(p - Double(index)) * rowHeight)
            }
            .blur(radius: min(5, speed / 7))
            // 円筒っぽい陰影
            LinearGradient(stops: [
                .init(color: .black.opacity(0.75), location: 0),
                .init(color: .black.opacity(0.0), location: 0.3),
                .init(color: .black.opacity(0.0), location: 0.7),
                .init(color: .black.opacity(0.75), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
            if let glow {
                Rectangle()
                    .fill(glow.opacity(0.18))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: rowHeight * 3)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(glow ?? Color.white.opacity(0.15), lineWidth: glow == nil ? 1 : 3)
                .shadow(color: glow ?? .clear, radius: 8)
        )
    }
}

/// 中段の有効ライン。揃ったときに光る
private struct PaylineView: View {
    let glowID: Int
    let reach: Bool

    var body: some View {
        Rectangle()
            .fill(Color.red.opacity(reach ? 0.9 : 0.55))
            .frame(height: reach ? 3 : 2)
            .shadow(color: .red, radius: reach ? 6 : 2)
            .overlay(
                Rectangle()
                    .fill(LinearGradient(colors: [.yellow, .white, .yellow], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 10)
                    .blur(radius: 3)
                    .keyframeAnimator(initialValue: 0.0, trigger: glowID) { content, v in
                        content.opacity(v)
                    } keyframes: { _ in
                        KeyframeTrack {
                            LinearKeyframe(1, duration: 0.05)
                            LinearKeyframe(0.3, duration: 0.15)
                            LinearKeyframe(1, duration: 0.15)
                            LinearKeyframe(0, duration: 0.5)
                        }
                    }
            )
            .allowsHitTesting(false)
    }
}

// MARK: - 期待度ゲージ

/// タメ中だけ出る期待度ゲージ。色は今の期待度、長さは時間とともに伸びる
private struct ExpectGauge: View {
    let color: ExpectColor?
    let progress: Double
    let now: Date
    let canSkip: Bool

    var body: some View {
        let t = now.timeIntervalSinceReferenceDate
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                if let color {
                    Capsule()
                        .fill(color == .rainbow ? AnyShapeStyle(RainbowFill.gradient(phase: t))
                                                : AnyShapeStyle(color.color))
                        .frame(width: max(12, geo.size.width * (0.15 + 0.85 * progress)))
                        .shadow(color: color.color, radius: 6 + 4 * sin(t * 20))
                    Text("期待度  \(color.label)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 2)
                        .padding(.leading, 10)
                    if canSkip {
                        // 裏ボタンの案内(控えめに点滅)
                        Text("リールを叩くと即告知")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35 + 0.3 * sin(t * 5)))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 10)
                    }
                }
            }
        }
        .frame(height: 14)
        .opacity(color == nil ? 0 : 1)
        .animation(.easeOut(duration: 0.2), value: color)
    }
}

// MARK: - 告知ランプ

/// 「心」ランプ。ボーナス確定で虹色に光る(ジャグラーの GOGO ランプの役)
struct KokoroLamp: View {
    let lit: Bool
    let now: Date

    var body: some View {
        let t = now.timeIntervalSinceReferenceDate
        ZStack {
            if lit {
                // 回る光線
                ForEach(0..<12, id: \.self) { i in
                    Capsule()
                        .fill(Color(hue: (Double(i) / 12 + t * 0.3).truncatingRemainder(dividingBy: 1),
                                    saturation: 0.9, brightness: 1).opacity(0.7))
                        .frame(width: 5, height: 34)
                        .offset(y: -40)
                        .rotationEffect(.degrees(Double(i) * 30 + t * 90))
                }
                .blendMode(.plusLighter)
            }
            Circle()
                .fill(lit ? AnyShapeStyle(RainbowFill.angular(phase: t * 0.5))
                          : AnyShapeStyle(Color(white: 0.16)))
                .frame(width: 54, height: 54)
                .overlay(Circle().stroke(.white.opacity(lit ? 0.9 : 0.2), lineWidth: 2))
                .shadow(color: lit ? .white : .clear, radius: lit ? 14 + 6 * sin(t * 10) : 0)
            Text("心")
                .font(.system(size: 28, weight: .black, design: .serif))
                .foregroundStyle(lit ? Color.white : Color(white: 0.35))
                .shadow(color: lit ? .pink : .clear, radius: 6)
        }
        .scaleEffect(lit ? 1 + 0.06 * sin(t * 12) : 1)
        .frame(width: 70, height: 70)
    }
}

private struct PayoutDisplay: View {
    let payout: Int
    let freeGame: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(freeGame ? "REPLAY" : "PAY")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
            Text(String(format: "%02ld", payout))
                .font(.system(size: 30, weight: .black, design: .monospaced))
                .foregroundStyle(Color(red: 1, green: 0.3, blue: 0.2))
                .shadow(color: .red, radius: 6)
                .contentTransition(.numericText(value: Double(payout)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.7)))
    }
}

// MARK: - 筐体のふちを走るランプ

private struct ChaseLights: View {
    let mood: SlotGame.Mood
    let theme: CabinetTheme
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let t = now.timeIntervalSinceReferenceDate
            let count = 36
            let speed: Double = {
                switch mood {
                case .normal: return 4
                case .zone: return 10
                case .reach: return 18
                case .bonus: return 14
                case .rush: return 22
                case .superRush: return 34
                case .freeze: return 0
                }
            }()
            ForEach(0..<count, id: \.self) { i in
                let point = perimeterPoint(Double(i) / Double(count), in: geo.size)
                let raw = (Double(i) - t * speed).truncatingRemainder(dividingBy: 6)
                let phase = raw < 0 ? raw + 6 : raw
                let on = mood != .freeze
                    && (phase < 1.2 || ((mood == .bonus || mood == .superRush) && i % 2 == Int(t * 6) % 2))
                Circle()
                    .fill(color(for: i, t: t))
                    .frame(width: 6, height: 6)
                    .opacity(on ? 1 : 0.18)
                    .shadow(color: on ? color(for: i, t: t) : .clear, radius: 4)
                    .position(point)
            }
        }
        .allowsHitTesting(false)
    }

    private func color(for i: Int, t: Double) -> Color {
        switch mood {
        case .normal:
            if theme == .rainbow {
                return Color(hue: (Double(i) / 36 + t * 0.1).truncatingRemainder(dividingBy: 1),
                             saturation: 0.8, brightness: 1)
            }
            return theme.chase
        case .zone: return i % 2 == 0 ? .orange : .yellow
        case .reach: return .red
        case .rush: return i % 2 == 0 ? Color(red: 1, green: 0.2, blue: 0.8) : .yellow
        case .bonus, .superRush:
            return Color(hue: (Double(i) / 36 + t * 0.5).truncatingRemainder(dividingBy: 1),
                         saturation: 0.9, brightness: 1)
        case .freeze: return .black
        }
    }

    /// 長方形の外周を 0〜1 でたどった点
    private func perimeterPoint(_ f: Double, in size: CGSize) -> CGPoint {
        let w = Double(size.width), h = Double(size.height)
        let total = 2 * (w + h)
        var d = f * total
        if d < w { return CGPoint(x: d, y: 0) }
        d -= w
        if d < h { return CGPoint(x: w, y: d) }
        d -= h
        if d < w { return CGPoint(x: w - d, y: h) }
        d -= w
        return CGPoint(x: 0, y: h - d)
    }
}

// MARK: - 虹色

enum RainbowFill {
    static func colors(phase: Double) -> [Color] {
        (0...6).map { i in
            Color(hue: (Double(i) / 6 + phase).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 1)
        }
    }

    static func gradient(phase: Double) -> LinearGradient {
        LinearGradient(colors: colors(phase: phase), startPoint: .leading, endPoint: .trailing)
    }

    static func angular(phase: Double) -> AngularGradient {
        AngularGradient(colors: colors(phase: phase), center: .center)
    }
}
