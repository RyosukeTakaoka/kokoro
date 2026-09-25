import Foundation

// MARK: - 抽選で決まるもの

/// ボーナスの種類。
enum BonusKind: Equatable {
    case big
    case reg

    /// 揃える図柄
    var symbol: SlotSymbol { self == .big ? .seven : .bar }
    /// ボーナス中に回せる回数
    var games: Int { self == .big ? 16 : 6 }
    var title: String { self == .big ? "BIG BONUS" : "REGULAR BONUS" }
}

/// 小役。
enum SmallRole: Equatable {
    case replay
    case bell
    case watermelon
    case cherry

    var symbol: SlotSymbol {
        switch self {
        case .replay: return .replay
        case .bell: return .bell
        case .watermelon: return .watermelon
        case .cherry: return .cherry
        }
    }

    /// 払い出し枚数(リプレイは次の 1 回が無料になるだけなので 0)
    var payout: Int {
        switch self {
        case .replay: return 0
        case .bell: return 8
        case .watermelon: return 10
        case .cherry: return 4
        }
    }
}

/// 期待度の色。青 → 緑 → 赤 → 金 → 虹 の順に熱い。
enum ExpectColor: Int, Comparable, CaseIterable {
    case blue
    case green
    case red
    case gold
    case rainbow

    static func < (lhs: ExpectColor, rhs: ExpectColor) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .blue: return "チャンス"
        case .green: return "チャンス!"
        case .red: return "激アツ!!"
        case .gold: return "超激アツ!!!"
        case .rainbow: return "確定!!!!"
        }
    }

    /// タメの長さ(秒)。熱いほど長く引っ張る(1.5〜2.5 秒が黄金帯、激アツだけ 3 秒)。
    var buildUpSeconds: Double {
        switch self {
        case .blue: return 1.6
        case .green: return 1.8
        case .red: return 2.3
        case .gold, .rainbow: return 3.0
        }
    }
}

/// リーチの最後の答え合わせのしかた。
enum RevealStyle: Equatable {
    /// タメが終わったら自動で答え
    case auto
    /// 「PUSH!」ボタンを押すと答え
    case push
    /// ボタンを連打してゲージを満タンにすると答え
    case renda
}

/// ボーナスが成立したことの知らせ方。
enum BonusNotice: Equatable {
    /// リーチ演出で揃える
    case reach
    /// レバーを叩いた瞬間にキュイーン(先告知)
    case preKyuin
    /// 3 本止めたあとにキュイーン(後告知)。揃えるのは次の回転
    case postLamp
}

/// いまの遊技状態。
enum GameMode: Equatable {
    case normal
    /// BIG のあとの連チャンしやすい区間
    case rush(gamesLeft: Int)
    /// ボーナス中
    case bonus(BonusKind, gamesLeft: Int)

    var isRush: Bool {
        if case .rush = self { return true }
        return false
    }

    var isBonus: Bool {
        if case .bonus = self { return true }
        return false
    }
}

/// リーチの中身。
struct ReachPlan: Equatable {
    /// 揃いかける図柄(7 か BAR)
    let symbol: SlotSymbol
    /// タメで最後にたどり着く色
    let color: ExpectColor
    let reveal: RevealStyle
    /// 第 3 停止ボタンの色(予告)
    let buttonHint: ExpectColor
    let wins: Bool
}

/// 1 回転ぶんの抽選結果と演出の台本。
struct SpinPlan: Equatable {
    enum Kind: Equatable {
        case miss
        case small(SmallRole)
        /// この回転でボーナスが成立
        case bonusHit(BonusKind)
        /// 前の回転で成立したボーナス図柄を揃える
        case align(BonusKind)
        /// ボーナス中の 1 回転
        case bonusGame(BonusKind)
    }

    var kind: Kind
    /// 最後に中段(有効ライン)に止まる図柄
    var centers: [SlotSymbol]
    var reach: ReachPlan?
    var notice: BonusNotice?
    /// 予告の強さ。0 = なし、1〜3 = チャンス〜激アツ、4 = 確定
    var yokoku: Int
    /// 払い出し枚数
    var payout: Int
    /// 3 本目が止まった時点でボーナスが始まるか
    var startsBonus: BonusKind?

    var isReplay: Bool {
        if case .small(.replay) = kind { return true }
        return false
    }
}

// MARK: - 抽選

enum SlotLottery {
    static let bet = 3
    static let bonusGamePayout = 8
    static let rushGames = 15

    struct Odds {
        var big: Double
        var reg: Double
        var replay: Double
        var bell: Double
        var watermelon: Double
        var cherry: Double
    }

    // 機械割は RUSH 込みでだいたい 101%(Python で 300 万回転シミュレーションして調整)。
    // リーチの信頼度は 青 3% / 緑 9% / 赤 44% / 金 78% / 虹 100%。

    /// 通常時。合算でだいたい 1/46 でボーナス。
    static let normalOdds = Odds(big: 1.0 / 80, reg: 1.0 / 110, replay: 1.0 / 7.3,
                                 bell: 1.0 / 12, watermelon: 1.0 / 50, cherry: 1.0 / 40)
    /// RUSH 中。合算 1/14.5 なので 15 回転で約 66% 連チャン。
    static let rushOdds = Odds(big: 1.0 / 28, reg: 1.0 / 30, replay: 1.0 / 7.3,
                               bell: 1.0 / 12, watermelon: 1.0 / 50, cherry: 1.0 / 40)

    static func draw<R: RandomNumberGenerator>(mode: GameMode, pendingBonus: BonusKind?,
                                               using rng: inout R) -> SpinPlan {
        if case .bonus(let kind, _) = mode {
            return bonusGamePlan(kind: kind, using: &rng)
        }
        if let pending = pendingBonus {
            let s = pending.symbol
            return SpinPlan(kind: .align(pending), centers: [s, s, s], reach: nil, notice: nil,
                            yokoku: 0, payout: 0, startsBonus: pending)
        }

        let odds = mode.isRush ? rushOdds : normalOdds
        let r = Double.random(in: 0..<1, using: &rng)
        var edge = odds.big
        if r < edge { return bonusPlan(.big, rush: mode.isRush, using: &rng) }
        edge += odds.reg
        if r < edge { return bonusPlan(.reg, rush: mode.isRush, using: &rng) }
        edge += odds.replay
        if r < edge { return smallPlan(.replay, using: &rng) }
        edge += odds.bell
        if r < edge { return smallPlan(.bell, using: &rng) }
        edge += odds.watermelon
        if r < edge { return smallPlan(.watermelon, using: &rng) }
        edge += odds.cherry
        if r < edge { return smallPlan(.cherry, using: &rng) }
        return missPlan(rush: mode.isRush, using: &rng)
    }

    // MARK: 役ごとの台本

    private static func bonusPlan<R: RandomNumberGenerator>(_ kind: BonusKind, rush: Bool,
                                                            using rng: inout R) -> SpinPlan {
        let s = kind.symbol
        let notice = pick([(BonusNotice.reach, rush ? 0.8 : 0.7),
                           (BonusNotice.postLamp, 0.18),
                           (BonusNotice.preKyuin, rush ? 0.02 : 0.12)], using: &rng)
        let yokoku = pick([(0, 0.2), (1, 0.2), (2, 0.28), (3, 0.24), (4, 0.08)], using: &rng)

        switch notice {
        case .reach:
            let color = pick([(ExpectColor.blue, 0.05), (ExpectColor.green, 0.10), (ExpectColor.red, 0.30),
                              (ExpectColor.gold, 0.35), (ExpectColor.rainbow, 0.20)], using: &rng)
            let reach = ReachPlan(symbol: s, color: color,
                                  reveal: revealStyle(for: color, using: &rng),
                                  buttonHint: buttonHint(for: color, wins: true, using: &rng),
                                  wins: true)
            return SpinPlan(kind: .bonusHit(kind), centers: [s, s, s], reach: reach, notice: .reach,
                            yokoku: yokoku, payout: 0, startsBonus: kind)
        case .preKyuin:
            return SpinPlan(kind: .bonusHit(kind), centers: [s, s, s], reach: nil, notice: .preKyuin,
                            yokoku: 0, payout: 0, startsBonus: kind)
        case .postLamp:
            return SpinPlan(kind: .bonusHit(kind), centers: plainMissCenters(using: &rng), reach: nil,
                            notice: .postLamp, yokoku: min(yokoku, 2), payout: 0, startsBonus: nil)
        }
    }

    private static func smallPlan<R: RandomNumberGenerator>(_ role: SmallRole, using rng: inout R) -> SpinPlan {
        let s = role.symbol
        // 小役でもたまに弱い予告が出る(予告 = ボーナス確定、にならないように)
        let yokoku = role == .watermelon
            ? pick([(0, 0.6), (1, 0.3), (2, 0.1)], using: &rng)
            : pick([(0, 0.9), (1, 0.1)], using: &rng)
        return SpinPlan(kind: .small(role), centers: [s, s, s], reach: nil, notice: nil,
                        yokoku: yokoku, payout: role.payout, startsBonus: nil)
    }

    private static func missPlan<R: RandomNumberGenerator>(rush: Bool, using rng: inout R) -> SpinPlan {
        let yokoku = pick([(0, 0.72), (1, 0.18), (2, 0.08), (3, 0.02)], using: &rng)
        // ハズレでもリーチ(ガセ)。ここで「あと 1 コマ」を見せる
        let reachRate = rush ? 0.14 : 0.09
        if Double.random(in: 0..<1, using: &rng) < reachRate {
            let s: SlotSymbol = Double.random(in: 0..<1, using: &rng) < 0.7 ? .seven : .bar
            let color = pick([(ExpectColor.blue, 0.55), (ExpectColor.green, 0.30), (ExpectColor.red, 0.12), (ExpectColor.gold, 0.03)],
                             using: &rng)
            let reach = ReachPlan(symbol: s, color: color,
                                  reveal: revealStyle(for: color, using: &rng),
                                  buttonHint: buttonHint(for: color, wins: false, using: &rng),
                                  wins: false)
            let others = SlotSymbol.allCases.filter { $0 != s }
            let third = others.randomElement(using: &rng) ?? .replay
            return SpinPlan(kind: .miss, centers: [s, s, third], reach: reach, notice: nil,
                            yokoku: yokoku, payout: 0, startsBonus: nil)
        }
        return SpinPlan(kind: .miss, centers: plainMissCenters(using: &rng), reach: nil, notice: nil,
                        yokoku: yokoku, payout: 0, startsBonus: nil)
    }

    private static func bonusGamePlan<R: RandomNumberGenerator>(kind: BonusKind, using rng: inout R) -> SpinPlan {
        let s = [SlotSymbol.bell, .watermelon, .cherry].randomElement(using: &rng) ?? .bell
        return SpinPlan(kind: .bonusGame(kind), centers: [s, s, s], reach: nil, notice: nil,
                        yokoku: 0, payout: bonusGamePayout, startsBonus: nil)
    }

    /// 何も揃わず、リーチにもならない並び。
    static func plainMissCenters<R: RandomNumberGenerator>(using rng: inout R) -> [SlotSymbol] {
        while true {
            let c = (0..<3).map { _ in SlotSymbol.allCases.randomElement(using: &rng) ?? .replay }
            let tripled = c[0] == c[1] && c[1] == c[2]
            let reach = c[0] == c[1] && c[0].isBonusSymbol
            if !tripled && !reach { return c }
        }
    }

    // MARK: 演出の味付け

    private static func revealStyle<R: RandomNumberGenerator>(for color: ExpectColor,
                                                              using rng: inout R) -> RevealStyle {
        switch color {
        case .blue, .green:
            return .auto
        case .red:
            return pick([(RevealStyle.push, 0.45), (RevealStyle.auto, 0.55)], using: &rng)
        case .gold, .rainbow:
            return pick([(RevealStyle.renda, 0.35), (RevealStyle.push, 0.35), (RevealStyle.auto, 0.30)], using: &rng)
        }
    }

    private static func buttonHint<R: RandomNumberGenerator>(for color: ExpectColor, wins: Bool,
                                                             using rng: inout R) -> ExpectColor {
        let r = Double.random(in: 0..<1, using: &rng)
        if wins && color == .rainbow && r < 0.3 { return .rainbow }
        if color >= .red && r < 0.35 { return .red }
        if color >= .green && r < 0.2 { return .green }
        return .blue
    }

    static func pick<T, R: RandomNumberGenerator>(_ items: [(T, Double)], using rng: inout R) -> T {
        let total = items.reduce(0) { $0 + $1.1 }
        var r = Double.random(in: 0..<total, using: &rng)
        for (item, weight) in items {
            if r < weight { return item }
            r -= weight
        }
        return items[items.count - 1].0
    }
}
