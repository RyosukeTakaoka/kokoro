import Foundation

// MARK: - 抽選で決まるもの

/// ボーナスの種類。
enum BonusKind: String, Codable, Equatable {
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
enum ExpectColor: Int, Comparable, CaseIterable, Codable {
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

    var name: String {
        switch self {
        case .blue: return "青"
        case .green: return "緑"
        case .red: return "赤"
        case .gold: return "金"
        case .rainbow: return "虹"
        }
    }

    /// タメの長さ(秒)。青・緑はサクサク、赤以上はじっくり引っ張る。
    var buildUpSeconds: Double {
        switch self {
        case .blue: return 1.0
        case .green: return 1.2
        case .red: return 2.3
        case .gold, .rainbow: return 3.0
        }
    }

    /// 赤以上は「最後のリールが半コマ上で粘る → 通り過ぎる」寸止めをする
    var usesHold: Bool { self >= .red }
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
    /// ロングフリーズ(BIG + SUPER RUSH 確定)
    case freeze
}

/// 普段と違う「違和感」。気づいた人だけ得をする前兆。出たらボーナスの期待度が高い(約 35%)。
enum Anomaly: Equatable, CaseIterable {
    /// 「心」ランプが一瞬だけ点いて消える
    case lampFlicker
    /// レバー音がいつもより少し高い
    case highLever
    /// レバーの振動が「トトン」と一瞬ズレる
    case hapticStutter
}

/// いまの遊技状態。
enum GameMode: Equatable {
    case normal
    /// BIG のあとの連チャンしやすい区間。isSuper = 上位の SUPER KOKORO RUSH
    case rush(gamesLeft: Int, isSuper: Bool)
    /// ボーナス中
    case bonus(BonusKind, gamesLeft: Int)

    var isRush: Bool {
        if case .rush = self { return true }
        return false
    }

    var isSuperRush: Bool {
        if case .rush(_, let isSuper) = self { return isSuper }
        return false
    }

    var isBonus: Bool {
        if case .bonus = self { return true }
        return false
    }
}

/// 台の設定(1〜6)。数字が大きいほどボーナスとベルが軽く、機械割が高い。
struct MachineSetting: Equatable {
    let level: Int
    let big: Double
    let reg: Double
    let bell: Double
    /// 機械割(Python で 400 万回転シミュレーションした値)
    let payoutRate: Double

    static let all: [MachineSetting] = [
        MachineSetting(level: 1, big: 1.0 / 138, reg: 1.0 / 180, bell: 1.0 / 13.2, payoutRate: 97.4),
        MachineSetting(level: 2, big: 1.0 / 133, reg: 1.0 / 172, bell: 1.0 / 13.0, payoutRate: 98.7),
        MachineSetting(level: 3, big: 1.0 / 128, reg: 1.0 / 163, bell: 1.0 / 12.8, payoutRate: 100.3),
        MachineSetting(level: 4, big: 1.0 / 122, reg: 1.0 / 152, bell: 1.0 / 12.5, payoutRate: 103.1),
        MachineSetting(level: 5, big: 1.0 / 116, reg: 1.0 / 142, bell: 1.0 / 12.2, payoutRate: 105.1),
        MachineSetting(level: 6, big: 1.0 / 109, reg: 1.0 / 132, bell: 1.0 / 11.9, payoutRate: 108.0),
    ]

    static func level(_ n: Int) -> MachineSetting {
        all[max(1, min(6, n)) - 1]
    }
}

/// ボーナス終了時に出る設定示唆
enum SettingHint: Int, Codable, CaseIterable {
    /// デフォルト(示唆なし)
    case white
    /// 奇数設定を示唆
    case blue
    /// 偶数設定を示唆
    case red
    /// 設定 4 以上確定
    case gold
    /// 設定 6 確定
    case rainbow

    var emoji: String {
        switch self {
        case .white: return "⚪️"
        case .blue: return "🔵"
        case .red: return "🔴"
        case .gold: return "🟡"
        case .rainbow: return "🌈"
        }
    }

    var meaning: String {
        switch self {
        case .white: return "示唆なし"
        case .blue: return "奇数設定を示唆"
        case .red: return "偶数設定を示唆"
        case .gold: return "設定4以上確定"
        case .rainbow: return "設定6確定"
        }
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
    var anomaly: Anomaly? = nil
    /// 天井(ハマりの救済)で当たった
    var isCeiling = false

    var isReplay: Bool {
        if case .small(.replay) = kind { return true }
        return false
    }

    var isBonusHit: Bool {
        if case .bonusHit = kind { return true }
        return false
    }
}

/// 抽選に必要な台の状況
struct DrawContext {
    var mode: GameMode
    var pendingBonus: BonusKind?
    var setting: MachineSetting
    /// 駆け抜け救済のチャンスゾーン中(ボーナス確率 2 倍)
    var inZone: Bool
    var gamesSinceBonus: Int
}

// MARK: - 抽選

enum SlotLottery {
    static let bet = 3
    static let bonusGamePayout = 8
    static let rushGames = 15
    static let zoneGames = 30
    /// この回転数ハマったら次は BIG
    static let ceiling = 600
    static let freezeRate = 1.0 / 4000
    /// RUSH 中にこの連チャン数に届いたら SUPER に昇格
    static let superChain = 4

    // 機械割は設定 1 ≈ 97% 〜 設定 6 ≈ 108%(RUSH・天井・ゾーン・フリーズ込み。Python でシミュレーション)。
    // リーチの信頼度は 青 3% / 緑 9% / 赤 44% / 金 78% / 虹 100%。

    /// RUSH 中: 合算 1/14.5 なので 15 回転で約 66% 連チャン
    static let rushBig = 1.0 / 28
    static let rushReg = 1.0 / 30
    /// SUPER RUSH 中: 合算 1/9.9 なので 15 回転で約 80% 連チャン
    static let superBig = 1.0 / 18
    static let superReg = 1.0 / 22

    static let replayRate = 1.0 / 7.3
    static let watermelonRate = 1.0 / 50
    static let cherryRate = 1.0 / 40

    static func draw<R: RandomNumberGenerator>(_ ctx: DrawContext, using rng: inout R) -> SpinPlan {
        if case .bonus(let kind, _) = ctx.mode {
            return bonusGamePlan(kind: kind, using: &rng)
        }
        if let pending = ctx.pendingBonus {
            let s = pending.symbol
            return SpinPlan(kind: .align(pending), centers: [s, s, s], reach: nil, notice: nil,
                            yokoku: 0, payout: 0, startsBonus: pending)
        }
        if !ctx.mode.isRush && ctx.gamesSinceBonus >= ceiling {
            return ceilingPlan()
        }
        if Double.random(in: 0..<1, using: &rng) < freezeRate {
            let s = SlotSymbol.seven
            return SpinPlan(kind: .bonusHit(.big), centers: [s, s, s], reach: nil, notice: .freeze,
                            yokoku: 0, payout: 0, startsBonus: .big)
        }

        var big: Double
        var reg: Double
        switch ctx.mode {
        case .rush(_, let isSuper):
            big = isSuper ? superBig : rushBig
            reg = isSuper ? superReg : rushReg
        default:
            big = ctx.setting.big
            reg = ctx.setting.reg
            if ctx.inZone {
                big *= 2
                reg *= 2
            }
        }

        let rush = ctx.mode.isRush
        let r = Double.random(in: 0..<1, using: &rng)
        let rates = [big, reg, replayRate, ctx.setting.bell, watermelonRate, cherryRate]
        var hit = rates.count
        var acc = 0.0
        for (i, rate) in rates.enumerated() {
            acc += rate
            if r < acc {
                hit = i
                break
            }
        }
        var plan: SpinPlan
        switch hit {
        case 0: plan = bonusPlan(.big, rush: rush, using: &rng)
        case 1: plan = bonusPlan(.reg, rush: rush, using: &rng)
        case 2: plan = smallPlan(.replay, using: &rng)
        case 3: plan = smallPlan(.bell, using: &rng)
        case 4: plan = smallPlan(.watermelon, using: &rng)
        case 5: plan = smallPlan(.cherry, using: &rng)
        default: plan = missPlan(rush: rush, using: &rng)
        }
        plan.anomaly = anomaly(for: plan, using: &rng)
        return plan
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
        case .preKyuin, .freeze:
            return SpinPlan(kind: .bonusHit(kind), centers: [s, s, s], reach: nil, notice: .preKyuin,
                            yokoku: 0, payout: 0, startsBonus: kind)
        case .postLamp:
            return SpinPlan(kind: .bonusHit(kind), centers: plainMissCenters(using: &rng), reach: nil,
                            notice: .postLamp, yokoku: min(yokoku, 2), payout: 0, startsBonus: nil)
        }
    }

    /// 天井: 虹リーチで必ず BIG
    private static func ceilingPlan() -> SpinPlan {
        let s = SlotSymbol.seven
        let reach = ReachPlan(symbol: s, color: .rainbow, reveal: .auto, buttonHint: .rainbow, wins: true)
        return SpinPlan(kind: .bonusHit(.big), centers: [s, s, s], reach: reach, notice: .reach, yokoku: 4,
                        payout: 0, startsBonus: .big, anomaly: nil, isCeiling: true)
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
        // ハズレでもリーチ(ガセ)
        let reachRate = rush ? 0.14 : 0.09
        if Double.random(in: 0..<1, using: &rng) < reachRate {
            let s: SlotSymbol = Double.random(in: 0..<1, using: &rng) < 0.7 ? .seven : .bar
            let color = pick([(ExpectColor.blue, 0.55), (ExpectColor.green, 0.30), (ExpectColor.red, 0.12),
                              (ExpectColor.gold, 0.03)], using: &rng)
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

    /// 違和感: ボーナス成立時は 45%、それ以外はごくまれ(出たときの信頼度 約 35%)
    private static func anomaly<R: RandomNumberGenerator>(for plan: SpinPlan, using rng: inout R) -> Anomaly? {
        let rate: Double
        switch plan.kind {
        case .bonusHit: rate = plan.notice == .preKyuin ? 0 : 0.45
        case .miss: rate = 0.015
        case .small: rate = 0.01
        case .align, .bonusGame: rate = 0
        }
        guard Double.random(in: 0..<1, using: &rng) < rate else { return nil }
        return Anomaly.allCases.randomElement(using: &rng)
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

    // MARK: 設定示唆

    /// ボーナス終了時の示唆ランプ。奇数設定は青、偶数設定は赤が出やすい。金は 4 以上、虹は 6 だけ
    static func settingHint<R: RandomNumberGenerator>(for setting: Int, using rng: inout R) -> SettingHint {
        let odd = setting % 2 == 1
        var items: [(SettingHint, Double)] = [
            (SettingHint.blue, odd ? 0.14 : 0.06),
            (SettingHint.red, odd ? 0.06 : 0.14),
        ]
        if setting >= 4 { items.append((SettingHint.gold, setting == 6 ? 0.06 : 0.04)) }
        if setting == 6 { items.append((SettingHint.rainbow, 0.03)) }
        let used = items.reduce(0) { $0 + $1.1 }
        items.append((SettingHint.white, 1 - used))
        return pick(items, using: &rng)
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
            return pick([(RevealStyle.renda, 0.35), (RevealStyle.push, 0.35), (RevealStyle.auto, 0.30)],
                        using: &rng)
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
