import Observation
import SwiftUI

/// 画面に出す大きな文字(リーチ! / BIG BONUS など)
struct SlamText: Equatable {
    enum Style: Equatable {
        case reach
        case yokoku(Int)
        case bonus
        case info
        case push
    }

    let id: Int
    let title: String
    let subtitle: String?
    let style: Style
    /// 出ている秒数
    let hold: Double
}

/// 画面全体を光らせる色
enum FlashStyle: Equatable {
    case white
    case color(ExpectColor)
    case rainbow
}

/// 画面揺れの 1 発
struct ShakeImpulse: Equatable {
    var start: Date
    var amplitude: Double
    var duration: Double
}

/// スロット 1 台ぶんの状態と、演出の段取り。
@MainActor
@Observable
final class SlotGame {
    enum Phase: Equatable {
        case idle
        case spinning
        /// リーチの最後の 1 本を止めたあとのタメ
        case buildUp
        /// PUSH / 連打の入力待ち
        case awaitingPush
        /// 答え合わせ・告知・ファンファーレなど(操作できない)
        case presenting
    }

    enum Mood: Equatable {
        case normal
        case reach
        case bonus
        case rush
    }

    // MARK: 遊技の状態

    private(set) var credits: Int
    private(set) var borrowed: Int
    private(set) var phase: Phase = .idle
    private(set) var mode: GameMode = .normal
    private(set) var reels = [ReelMotion(), ReelMotion(), ReelMotion()]
    private(set) var stoppedCount = 3
    private(set) var plan: SpinPlan?
    private(set) var freeGame = false
    private(set) var pendingBonus: BonusKind?
    private(set) var lastPayout = 0

    // データカウンター
    private(set) var gamesSinceBonus: Int
    private(set) var totalGames: Int
    private(set) var bigCount: Int
    private(set) var regCount: Int
    private(set) var history: [BonusRecord] = []

    // ボーナス・RUSH
    private(set) var bonusGained = 0
    private(set) var rushChain = 0
    private(set) var rushTotal = 0

    // MARK: 演出の状態(ビューが読む)

    private(set) var lampLit = false
    private(set) var reachActive = false
    private(set) var aura: ExpectColor?
    private(set) var buttonHint: ExpectColor?
    /// タメの開始時刻と長さ(進み具合は時刻から計算する)
    private(set) var buildUpStart: Date?
    private(set) var buildUpDuration = 1.0
    private(set) var zoom: CGFloat = 1
    private(set) var dim = 0.0
    private(set) var desaturate = false
    private(set) var rays = false
    private(set) var shakeBase = 0.0
    private(set) var shake = ShakeImpulse(start: .distantPast, amplitude: 0, duration: 0.1)
    private(set) var flashID = 0
    private(set) var flashStyle: FlashStyle = .white
    private(set) var flashStrength = 0.0
    private(set) var slam: SlamText?
    private(set) var pushStyle: RevealStyle?
    private(set) var rendaCount = 0
    let rendaTarget = 12
    private(set) var paylineGlowID = 0

    var auto = false {
        didSet { if auto { startAutoLoop() } }
    }

    var soundOn: Bool {
        didSet {
            sound.isEnabled = soundOn
            UserDefaults.standard.set(soundOn, forKey: Keys.sound)
        }
    }

    var hapticsOn: Bool {
        didSet {
            haptics.isEnabled = hapticsOn
            UserDefaults.standard.set(hapticsOn, forKey: Keys.haptics)
        }
    }

    struct BonusRecord: Equatable, Identifiable {
        let id: Int
        let kind: BonusKind
        let games: Int
    }

    let particles = ParticleSystem()
    private let sound = SoundEngine.shared
    private let haptics = HapticEngine.shared
    @ObservationIgnored private var rng = SystemRandomNumberGenerator()
    @ObservationIgnored private var stopsEnabledAt = Date.distantPast
    @ObservationIgnored private var heldIndex = 0
    @ObservationIgnored private var slamCounter = 0
    @ObservationIgnored private var historyCounter = 0
    @ObservationIgnored private var autoRunning = false
    @ObservationIgnored private var nextAutoAction = Date.distantPast
    @ObservationIgnored private var pushTimeout: Task<Void, Never>?

    static let startingCredits = 500
    static let refillAmount = 500

    private enum Keys {
        static let credits = "credits"
        static let borrowed = "borrowed"
        static let games = "gamesSinceBonus"
        static let total = "totalGames"
        static let big = "bigCount"
        static let reg = "regCount"
        static let sound = "soundOn"
        static let haptics = "hapticsOn"
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [Keys.credits: Self.startingCredits, Keys.sound: true, Keys.haptics: true])
        credits = d.integer(forKey: Keys.credits)
        borrowed = d.integer(forKey: Keys.borrowed)
        gamesSinceBonus = d.integer(forKey: Keys.games)
        totalGames = d.integer(forKey: Keys.total)
        bigCount = d.integer(forKey: Keys.big)
        regCount = d.integer(forKey: Keys.reg)
        soundOn = d.bool(forKey: Keys.sound)
        hapticsOn = d.bool(forKey: Keys.haptics)
        sound.isEnabled = soundOn
        haptics.isEnabled = hapticsOn
        // 起動時のリールはばらばらの位置に
        for i in 0..<3 {
            reels[i].state = .stopped(position: Double(Int.random(in: 0..<ReelStrip.length)))
        }
        sound.prewarm()
    }

    // MARK: 表示用

    var mood: Mood {
        if mode.isBonus { return .bonus }
        if reachActive { return .reach }
        if mode.isRush { return .rush }
        return .normal
    }

    /// 借りたぶんを引いた差枚
    var netMedals: Int { credits - borrowed - Self.startingCredits }

    var canPullLever: Bool {
        phase == .idle && (freeGame || credits >= SlotLottery.bet)
    }

    var needsRefill: Bool {
        phase == .idle && !freeGame && credits < SlotLottery.bet
    }

    /// 次に止めるリール(0〜2)。全部止まっていれば nil
    var nextReel: Int? {
        phase == .spinning && stoppedCount < 3 ? stoppedCount : nil
    }

    var isLastReelReach: Bool { reachActive && stoppedCount == 2 }

    /// タメの進み具合(0〜1)。タメ中でなければ 0
    func buildUpProgress(at now: Date) -> Double {
        guard let start = buildUpStart else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / buildUpDuration))
    }

    // MARK: - 操作

    func pullLever() {
        guard canPullLever else { return }
        let now = Date()
        if freeGame {
            freeGame = false
        } else {
            credits -= SlotLottery.bet
        }
        lastPayout = 0
        totalGames += 1
        if !mode.isBonus { gamesSinceBonus += 1 }

        let newPlan = SlotLottery.draw(mode: mode, pendingBonus: pendingBonus, using: &rng)
        plan = newPlan
        stoppedCount = 0
        reachActive = false
        aura = nil
        buttonHint = nil
        buildUpStart = nil
        rays = false
        desaturate = false
        phase = .spinning
        for i in 0..<3 {
            reels[i].startSpin(at: now.addingTimeInterval(Double(i) * 0.04))
        }
        stopsEnabledAt = now.addingTimeInterval(0.4)
        sound.play(.lever)
        haptics.lever()

        if newPlan.notice == .preKyuin {
            // 先告知: レバーを叩いた瞬間にランプ点灯
            run { game in
                await game.wait(0.08)
                game.lightLamp(big: false)
            }
        } else if newPlan.yokoku > 0 {
            let level = newPlan.yokoku
            run { game in
                await game.wait(0.12)
                game.showYokoku(level)
            }
        }
        save()
    }

    func pressStop() {
        guard phase == .spinning, stoppedCount < 3, let plan else { return }
        let now = Date()
        guard now >= stopsEnabledAt else { return }
        let i = stoppedCount

        if i == 2, let reach = plan.reach {
            beginBuildUp(reach: reach, plan: plan)
            return
        }

        var above: SlotSymbol?
        if case .miss = plan.kind, plan.reach == nil, Int.random(in: 0..<8) == 0 {
            above = .seven // 「惜しい」ちら見せ
        }
        let landing = reels[i].stop(at: now, center: plan.centers[i], above: above)
        stoppedCount += 1
        sound.play(.stop, volume: 0.9)
        haptics.stop(strong: mode.isBonus)
        // 前のリールが着地する前に次を押せないように、少し間をあける
        stopsEnabledAt = now.addingTimeInterval(0.12)

        if i == 1, plan.reach != nil {
            stopsEnabledAt = now.addingTimeInterval(landing + 0.7)
            run { game in
                await game.wait(landing * 0.6)
                game.announceReach(plan.reach!)
            }
        }
        if i == 2 {
            phase = .presenting
            run { game in
                await game.wait(landing * 0.7)
                await game.resolve(plan)
            }
        } else if mode.isBonus {
            flash(.color(.gold), strength: 0.18)
        }
    }

    /// PUSH ボタン / 画面の連打
    func tapPush() {
        guard phase == .awaitingPush, let style = pushStyle else { return }
        switch style {
        case .push, .auto:
            sound.play(.push)
            haptics.push(level: 1)
            reveal()
        case .renda:
            rendaCount += 1
            let level = Double(rendaCount) / Double(rendaTarget)
            sound.play(.tick(rendaCount))
            haptics.push(level: level)
            flash(.color(aura ?? .red), strength: 0.12 + 0.25 * level)
            kick(3 + 7 * level, duration: 0.15)
            particles.burst(.spark, count: 10, at: UnitPoint(x: 0.5, y: 0.78), power: 0.5 + level, hue: 0.12)
            if rendaCount >= rendaTarget {
                reveal()
            }
        }
    }

    func refill() {
        guard needsRefill else { return }
        credits += Self.refillAmount
        borrowed += Self.refillAmount
        sound.play(.coin)
        haptics.coin(0.8)
        save()
    }

    func resetData() {
        guard phase == .idle else { return }
        credits = Self.startingCredits
        borrowed = 0
        gamesSinceBonus = 0
        totalGames = 0
        bigCount = 0
        regCount = 0
        history = []
        mode = .normal
        pendingBonus = nil
        lampLit = false
        freeGame = false
        rushChain = 0
        rushTotal = 0
        sound.stopMusic()
        save()
    }

    func appBecameActive() {
        haptics.wake()
        switch mode {
        case .bonus: sound.playMusic(.bonus)
        case .rush: sound.playMusic(.rush)
        case .normal: break
        }
    }

    // MARK: - リーチ

    private func announceReach(_ reach: ReachPlan) {
        reachActive = true
        buttonHint = reach.buttonHint
        sound.play(.reach)
        haptics.reach()
        haptics.startHeartbeat(rate: reach.buttonHint >= .red ? 2.0 : 1.4)
        // オートでも最後の 1 本は少し溜めてから押す
        nextAutoAction = Date().addingTimeInterval(1.1)
        flash(.color(.red), strength: 0.55)
        kick(8, duration: 0.35)
        showSlam("リーチ!", style: .reach, hold: 0.9)
        particles.burst(.spark, count: 60, at: UnitPoint(x: 0.35, y: 0.42), power: 0.8, hue: 0.0)
        if reach.buttonHint == .rainbow {
            flash(.rainbow, strength: 0.6)
            sound.play(.yokoku(4), volume: 0.8)
        }
    }

    private func beginBuildUp(reach: ReachPlan, plan: SpinPlan) {
        let now = Date()
        phase = .buildUp
        stoppedCount = 3
        let missCenter: SlotSymbol = reach.wins ? .replay : plan.centers[2]
        heldIndex = reels[2].hold(at: now, symbol: reach.symbol, missCenter: missCenter)

        // ① 静寂: 音も振動も一瞬すべて消して、画面を暗くする
        haptics.stopHeartbeat()
        sound.silence()
        sound.play(.cut, volume: 0.8)
        haptics.freeze()
        withAnimation(.easeOut(duration: 0.12)) { dim = 0.6 }

        run { game in
            await game.wait(0.28)
            await game.runBuildUp(reach)
        }
    }

    /// ② タメ: 色が 青 → … → 答えの色 へ段階的に上がり、音と振動がせり上がる
    private func runBuildUp(_ reach: ReachPlan) async {
        let seconds = reach.color.buildUpSeconds
        let steps = reach.color.rawValue + 1
        withAnimation(.easeOut(duration: 0.25)) { dim = 0.25 }
        buildUpStart = Date()
        buildUpDuration = seconds
        withAnimation(.easeIn(duration: seconds)) {
            zoom = 1.08
        }
        sound.play(.riser(tenths: Int((seconds * 10).rounded())), volume: 0.9)
        haptics.buildUp(seconds: seconds)

        for k in 0..<steps {
            let color = ExpectColor(rawValue: k) ?? .blue
            aura = color
            shakeBase = 0.6 + Double(k) * 1.4
            sound.play(.step(k), volume: 0.85)
            haptics.step(k)
            flash(color == .rainbow ? .rainbow : .color(color), strength: 0.28 + 0.1 * Double(k))
            particles.burst(.ember, count: 40 + 25 * k, at: UnitPoint(x: 0.5, y: 0.42),
                            hue: color == .rainbow ? nil : color.hue)
            if color >= .red {
                showSlam(color.label, style: .yokoku(k), hold: seconds / Double(steps))
            }
            await wait(seconds / Double(steps))
        }

        switch reach.reveal {
        case .auto:
            reveal()
        case .push, .renda:
            waitForPush(reach.reveal)
        }
    }

    /// ③ PUSH / 連打待ち
    private func waitForPush(_ style: RevealStyle) {
        phase = .awaitingPush
        pushStyle = style
        rendaCount = 0
        shakeBase = 1.5
        sound.play(.push)
        haptics.push(level: 0.6)
        showSlam(style == .renda ? "連打!!" : "PUSH!!", style: .push, hold: 1.2)
        nextAutoAction = Date().addingTimeInterval(0.9)
        pushTimeout?.cancel()
        pushTimeout = run { game in
            // 押さないままでも 7 秒で答えを出す。待っている間は鼓動で急かす
            for _ in 0..<14 {
                await game.wait(0.5)
                guard game.phase == .awaitingPush else { return }
                game.haptics.push(level: 0.3)
            }
            if game.phase == .awaitingPush { game.reveal() }
        }
    }

    /// ④ 答え合わせ
    private func reveal() {
        guard phase == .buildUp || phase == .awaitingPush, let plan, let reach = plan.reach else { return }
        pushTimeout?.cancel()
        phase = .presenting
        pushStyle = nil
        let now = Date()
        let duration = reels[2].settle(at: now, heldIndex: heldIndex, wins: reach.wins)
        shakeBase = 0
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            zoom = 1
            dim = 0
        }
        run { game in
            await game.wait(duration * 0.9)
            if reach.wins {
                game.sound.restoreMusic()
                await game.celebrate(plan.startsBonus ?? .big)
            } else {
                game.missAfterReach()
                await game.finishSpin(plan)
            }
        }
    }

    private func missAfterReach() {
        sound.restoreMusic()
        sound.play(.lose)
        haptics.lose()
        reachActive = false
        aura = nil
        buildUpStart = nil
        withAnimation(.easeOut(duration: 0.2)) { desaturate = true }
        showSlam("あと1コマ…", style: .info, hold: 1.1)
        run { game in
            await game.wait(0.9)
            withAnimation(.easeInOut(duration: 0.6)) { game.desaturate = false }
        }
    }

    // MARK: - 結果

    private func resolve(_ plan: SpinPlan) async {
        switch plan.kind {
        case .miss:
            await finishSpin(plan)

        case .small(let role):
            if role == .replay {
                freeGame = true
                sound.play(.smallWin, volume: 0.7)
                haptics.smallWin()
                showSlam("REPLAY", style: .info, hold: 0.7)
            } else {
                sound.play(.smallWin)
                haptics.smallWin()
                paylineGlowID += 1
                particles.burst(.spark, count: 40, at: UnitPoint(x: 0.5, y: 0.42), power: 0.6,
                                hue: role == .bell ? 0.14 : (role == .watermelon ? 0.33 : 0.95))
                await payOut(role.payout)
            }
            await finishSpin(plan)

        case .bonusHit(let kind):
            if plan.notice == .postLamp {
                // 後告知: 一瞬の間のあとランプ点灯。揃えるのは次の回転
                await wait(0.35)
                lightLamp(big: true)
                pendingBonus = kind
                await wait(1.2)
                await finishSpin(plan)
            } else {
                await celebrate(kind)
            }

        case .align(let kind):
            await celebrate(kind)

        case .bonusGame:
            paylineGlowID += 1
            sound.play(.smallWin, volume: 0.8)
            haptics.smallWin()
            particles.burst(.coin, count: 14, at: UnitPoint(x: 0.5, y: 1.02), power: 0.8)
            await payOut(plan.payout)
            bonusGained += plan.payout
            await finishSpin(plan)
        }
    }

    /// 払い出し: 1 枚ずつ数字を回して、チャリチャリ鳴らす
    private func payOut(_ amount: Int) async {
        guard amount > 0 else { return }
        lastPayout = 0
        for n in 0..<amount {
            credits += 1
            lastPayout += 1
            if n % 2 == 0 {
                sound.play(.coin, volume: 0.55)
                haptics.coin(0.35)
            }
            await wait(0.028)
        }
    }

    /// 告知ランプ点灯(キュイーン)
    private func lightLamp(big: Bool) {
        lampLit = true
        sound.play(.kyuin)
        haptics.kyuin()
        flash(.rainbow, strength: big ? 0.9 : 0.7)
        kick(big ? 10 : 6, duration: 0.5)
        particles.burst(.spark, count: big ? 120 : 70, at: UnitPoint(x: 0.5, y: 0.66), power: 1.1)
        if big {
            showSlam("BONUS 確定!!", style: .bonus, hold: 1.4)
        }
    }

    /// 大当たりの爆発 → ファンファーレ → ボーナス開始
    private func celebrate(_ kind: BonusKind) async {
        phase = .presenting
        haptics.stopHeartbeat()
        let wasLit = lampLit
        lampLit = true
        rays = true
        aura = .rainbow
        sound.play(.boom)
        if !wasLit { sound.play(.kyuin, volume: 0.8) }
        haptics.explosion()
        flash(.white, strength: 1)
        kick(22, duration: 1.1)
        paylineGlowID += 1
        particles.burst(.confetti, count: 260, at: UnitPoint(x: 0.5, y: 0.45), power: 1.1)
        particles.burst(.spark, count: 160, at: UnitPoint(x: 0.5, y: 0.42), power: 1.4)
        particles.burst(.coin, count: 50, at: UnitPoint(x: 0.5, y: 1.02), power: 1.2)
        showSlam(kind.title, style: .bonus, hold: 2.6)

        await wait(0.35)
        sound.play(.fanfare)
        haptics.fanfare()
        flash(.rainbow, strength: 0.6)
        await wait(0.85)
        particles.burst(.confetti, count: 160, at: UnitPoint(x: 0.2, y: 0.3), power: 0.9)
        particles.burst(.confetti, count: 160, at: UnitPoint(x: 0.8, y: 0.3), power: 0.9)
        haptics.explosion()
        kick(10, duration: 0.6)
        await wait(1.6)
        startBonus(kind)
    }

    private func startBonus(_ kind: BonusKind) {
        if mode.isRush {
            rushChain += 1
        } else {
            rushChain = 1
            rushTotal = 0
        }
        pendingBonus = nil
        reachActive = false
        rays = false
        aura = nil
        buildUpStart = nil
        bonusGained = 0
        historyCounter += 1
        history.insert(BonusRecord(id: historyCounter, kind: kind, games: gamesSinceBonus), at: 0)
        if history.count > 12 { history.removeLast() }
        gamesSinceBonus = 0
        if kind == .big { bigCount += 1 } else { regCount += 1 }
        mode = .bonus(kind, gamesLeft: kind.games)
        sound.playMusic(.bonus)
        phase = .idle
        nextAutoAction = Date().addingTimeInterval(0.6)
        save()
    }

    private func endBonus(_ kind: BonusKind) async {
        phase = .presenting
        sound.stopMusic()
        sound.play(.bonusEnd)
        haptics.smallWin()
        lampLit = false
        rushTotal += bonusGained
        showSlam("BONUS END", subtitle: "+\(bonusGained)枚", style: .info, hold: 1.8)
        await wait(1.9)

        if kind == .big {
            mode = .rush(gamesLeft: SlotLottery.rushGames)
            sound.play(.rushStart)
            sound.playMusic(.rush)
            haptics.fanfare()
            flash(.rainbow, strength: 0.8)
            kick(12, duration: 0.6)
            particles.burst(.confetti, count: 220, at: UnitPoint(x: 0.5, y: 0.4), power: 1)
            let chain = rushChain >= 2 ? "\(rushChain)連中!" : "連チャンのチャンス!"
            showSlam("KOKORO RUSH", subtitle: chain, style: .bonus, hold: 2.0)
            await wait(1.8)
        } else {
            endRush()
        }
    }

    private func endRush() {
        if rushChain >= 2 {
            showSlam("RUSH 終了", subtitle: "\(rushChain)連  +\(rushTotal)枚", style: .info, hold: 2.2)
        }
        mode = .normal
        rushChain = 0
        rushTotal = 0
        sound.stopMusic()
    }

    private func finishSpin(_ plan: SpinPlan) async {
        haptics.stopHeartbeat()
        reachActive = false
        buttonHint = nil
        aura = nil
        shakeBase = 0
        buildUpStart = nil

        switch mode {
        case .bonus(let kind, let left):
            if left <= 1 {
                await endBonus(kind)
            } else {
                mode = .bonus(kind, gamesLeft: left - 1)
            }
        case .rush(let left):
            if case .bonusHit = plan.kind { break }
            if pendingBonus != nil { break }
            if left <= 1 {
                endRush()
            } else {
                mode = .rush(gamesLeft: left - 1)
            }
        case .normal:
            break
        }
        phase = .idle
        nextAutoAction = Date().addingTimeInterval(0.45)
        save()
    }

    // MARK: - 予告

    private func showYokoku(_ level: Int) {
        let texts = ["", "チャンス?", "チャンス!", "激アツ!!", "確定!!!"]
        let colors: [ExpectColor] = [.blue, .blue, .green, .red, .rainbow]
        let color = colors[min(level, 4)]
        sound.play(.yokoku(level))
        haptics.step(level)
        flash(color == .rainbow ? .rainbow : .color(color), strength: 0.2 + 0.12 * Double(level))
        if level >= 3 { kick(6, duration: 0.4) }
        showSlam(texts[min(level, 4)], style: .yokoku(color.rawValue), hold: 1.0)
    }

    // MARK: - 小道具

    private func showSlam(_ title: String, subtitle: String? = nil, style: SlamText.Style, hold: Double) {
        slamCounter += 1
        slam = SlamText(id: slamCounter, title: title, subtitle: subtitle, style: style, hold: hold)
    }

    private func flash(_ style: FlashStyle, strength: Double) {
        flashStyle = style
        flashStrength = strength
        flashID += 1
    }

    private func kick(_ amplitude: Double, duration: Double) {
        shake = ShakeImpulse(start: Date(), amplitude: amplitude, duration: duration)
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(credits, forKey: Keys.credits)
        d.set(borrowed, forKey: Keys.borrowed)
        d.set(gamesSinceBonus, forKey: Keys.games)
        d.set(totalGames, forKey: Keys.total)
        d.set(bigCount, forKey: Keys.big)
        d.set(regCount, forKey: Keys.reg)
    }

    fileprivate func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    @discardableResult
    private func run(_ body: @escaping @MainActor (SlotGame) async -> Void) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await body(self)
        }
    }

    // MARK: - オート

    private func startAutoLoop() {
        guard !autoRunning else { return }
        autoRunning = true
        run { game in
            while game.auto {
                await game.wait(0.08)
                game.autoStep()
            }
            game.autoRunning = false
        }
    }

    private func autoStep() {
        let now = Date()
        guard now >= nextAutoAction else { return }
        switch phase {
        case .idle:
            if needsRefill {
                auto = false
                return
            }
            pullLever()
            nextAutoAction = now.addingTimeInterval(0.55)
        case .spinning:
            guard now >= stopsEnabledAt else { return }
            pressStop()
            nextAutoAction = now.addingTimeInterval(0.3)
        case .awaitingPush:
            tapPush()
            nextAutoAction = now.addingTimeInterval(pushStyle == .renda ? 0.09 : 0.8)
        case .buildUp, .presenting:
            break
        }
    }
}

extension ExpectColor {
    var hue: Double {
        switch self {
        case .blue: return 0.6
        case .green: return 0.36
        case .red: return 0.0
        case .gold: return 0.13
        case .rainbow: return 0.8
        }
    }

    var color: Color {
        switch self {
        case .blue: return Color(red: 0.2, green: 0.55, blue: 1)
        case .green: return Color(red: 0.2, green: 0.95, blue: 0.45)
        case .red: return Color(red: 1, green: 0.15, blue: 0.2)
        case .gold: return Color(red: 1, green: 0.8, blue: 0.15)
        case .rainbow: return Color(red: 1, green: 0.4, blue: 0.9)
        }
    }
}
