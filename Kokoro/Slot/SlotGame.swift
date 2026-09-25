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

/// 実績解除のお知らせ
struct AchievementToast: Equatable {
    let id: Int
    let achievement: Achievement
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

/// 1 台のスロットに座っている間の状態と、演出の段取り。
/// メダル・実績はプレイヤー(`PlayerStore`)に、台のデータはホール(`HallStore`)に書き込む。
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
        /// 答え合わせ・告知・ファンファーレ・フリーズなど(操作できない)
        case presenting
    }

    enum Mood: Equatable {
        case normal
        case zone
        case reach
        case bonus
        case rush
        case superRush
        case freeze
    }

    let machineNumber: Int
    let setting: MachineSetting
    let player: PlayerStore
    let hall: HallStore

    // MARK: 遊技の状態

    private(set) var phase: Phase = .idle
    private(set) var mode: GameMode = .normal
    private(set) var reels = [ReelMotion(), ReelMotion(), ReelMotion()]
    private(set) var stoppedCount = 3
    private(set) var plan: SpinPlan?
    private(set) var freeGame = false
    private(set) var pendingBonus: BonusKind?
    private(set) var lastPayout = 0
    /// 駆け抜けたあとのチャンスゾーンの残り回転数
    private(set) var zoneGamesLeft = 0

    // ボーナス・RUSH
    private(set) var bonusGained = 0
    private(set) var rushChain = 0
    private(set) var rushTotal = 0

    // MARK: 演出の状態(ビューが読む)

    private(set) var lampLit = false
    /// 違和感: ランプが一瞬だけ点く
    private(set) var lampFlicker = false
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
    private(set) var freezeActive = false
    private(set) var shakeBase = 0.0
    private(set) var shake = ShakeImpulse(start: .distantPast, amplitude: 0, duration: 0.1)
    private(set) var flashID = 0
    private(set) var flashStyle: FlashStyle = .white
    private(set) var flashStrength = 0.0
    private(set) var slam: SlamText?
    private(set) var toast: AchievementToast?
    private(set) var pushStyle: RevealStyle?
    private(set) var rendaCount = 0
    let rendaTarget = 12
    private(set) var paylineGlowID = 0

    var auto = false {
        didSet { if auto { startAutoLoop() } }
    }

    let particles = ParticleSystem()
    private let sound = SoundEngine.shared
    private let haptics = HapticEngine.shared
    @ObservationIgnored private var rng = SystemRandomNumberGenerator()
    @ObservationIgnored private var stopsEnabledAt = Date.distantPast
    @ObservationIgnored private var heldIndex = 0
    /// 最後のリールが半コマ上で粘っているか(赤以上のリーチ)
    @ObservationIgnored private var holdingThird = false
    @ObservationIgnored private var currentReach: ReachPlan?
    /// ボーナスが成立した回転の「ハマり回転数」(1G 連の判定用)
    @ObservationIgnored private var hitGames = 0
    /// ボーナス後に RUSH へ入るか / SUPER で入るか
    @ObservationIgnored private var rushAfterBonus = false
    @ObservationIgnored private var superAfterBonus = false
    @ObservationIgnored private var slamCounter = 0
    @ObservationIgnored private var toastCounter = 0
    @ObservationIgnored private var autoRunning = false
    @ObservationIgnored private var nextAutoAction = Date.distantPast
    @ObservationIgnored private var pushTimeout: Task<Void, Never>?

    init(machineNumber: Int, player: PlayerStore, hall: HallStore) {
        self.machineNumber = machineNumber
        self.player = player
        self.hall = hall
        setting = hall.setting(for: machineNumber)
        // 起動時のリールはばらばらの位置に
        for i in 0..<3 {
            reels[i].state = .stopped(position: Double(Int.random(in: 0..<ReelStrip.length)))
        }
        sound.bgmStyle = player.bgm
        sound.prewarm()
        hall.update(machineNumber) { $0.occupant = "me" }
    }

    // MARK: 表示用

    var machineData: MachineData { hall.data(for: machineNumber) }
    var credits: Int { player.credits }

    var mood: Mood {
        if freezeActive { return .freeze }
        if mode.isBonus { return .bonus }
        if reachActive { return .reach }
        if mode.isSuperRush { return .superRush }
        if mode.isRush { return .rush }
        if zoneGamesLeft > 0 { return .zone }
        return .normal
    }

    var canPullLever: Bool {
        phase == .idle && (freeGame || player.credits >= SlotLottery.bet)
    }

    var needsRefill: Bool {
        phase == .idle && !freeGame && player.credits < SlotLottery.bet
    }

    /// 席を立てるか。ボーナス・RUSH・ゾーン・告知後・リプレイ中は離れられない
    var canLeave: Bool {
        phase == .idle && mode == .normal && pendingBonus == nil && zoneGamesLeft == 0 && !freeGame
    }

    /// 次に止めるリール(0〜2)。全部止まっていれば nil
    var nextReel: Int? {
        phase == .spinning && stoppedCount < 3 ? stoppedCount : nil
    }

    var isLastReelReach: Bool { reachActive && stoppedCount == 2 }

    /// 通常 RUSH で、あと何連で SUPER に上がるか
    var chainsToSuper: Int? {
        guard case .rush(_, let isSuper) = mode, !isSuper else { return nil }
        return max(0, SlotLottery.superChain - rushChain)
    }

    /// タメを飛ばせるか(赤以上のリーチのタメ中だけ)
    var canSkipBuildUp: Bool {
        phase == .buildUp && (currentReach?.color ?? .blue) >= .red
    }

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
            player.credits -= SlotLottery.bet
        }
        lastPayout = 0
        let inBonus = mode.isBonus
        hall.update(machineNumber) { d in
            d.totalGames += 1
            if !inBonus { d.gamesSinceBonus += 1 }
        }
        player.lifetimeSpins += 1

        let data = machineData
        let context = DrawContext(mode: mode, pendingBonus: pendingBonus, setting: setting,
                                  inZone: zoneGamesLeft > 0 && mode == .normal,
                                  gamesSinceBonus: data.gamesSinceBonus)
        let newPlan = SlotLottery.draw(context, using: &rng)
        plan = newPlan
        if newPlan.isBonusHit { hitGames = data.gamesSinceBonus }
        if case .small(.bell) = newPlan.kind {
            hall.update(machineNumber) { $0.bellCount += 1 }
        }
        stoppedCount = 0
        reachActive = false
        currentReach = nil
        aura = nil
        buttonHint = nil
        buildUpStart = nil
        rays = false
        desaturate = false
        checkSpinAchievements()

        if newPlan.notice == .freeze {
            stoppedCount = 3
            phase = .presenting
            run { game in await game.runFreeze() }
            return
        }

        phase = .spinning
        for i in 0..<3 {
            reels[i].startSpin(at: now.addingTimeInterval(Double(i) * 0.04))
        }
        stopsEnabledAt = now.addingTimeInterval(0.4)

        // 違和感: 気づく人だけ気づく、いつもとほんの少し違うレバー
        switch newPlan.anomaly {
        case .highLever:
            sound.play(.leverHigh)
            haptics.lever()
        case .hapticStutter:
            sound.play(.lever)
            haptics.leverStutter()
        case .lampFlicker:
            sound.play(.lever)
            haptics.lever()
            run { game in
                await game.wait(0.35)
                game.lampFlicker = true
                await game.wait(0.05)
                game.lampFlicker = false
            }
        case nil:
            sound.play(.lever)
            haptics.lever()
        }
        if newPlan.anomaly != nil { player.anomaliesSeen += 1 }

        if newPlan.notice == .preKyuin {
            // 先告知: レバーを叩いた瞬間にランプ点灯
            run { game in
                await game.wait(0.08)
                game.lightLamp(big: false)
            }
        } else if newPlan.isCeiling {
            award(.ceiling)
            run { game in
                await game.wait(0.12)
                game.sound.play(.yokoku(4))
                game.haptics.step(4)
                game.flash(.rainbow, strength: 0.8)
                game.kick(10, duration: 0.5)
                game.showSlam("天井到達!!", subtitle: "\(SlotLottery.ceiling)G ハマりの救済", style: .bonus, hold: 1.4)
            }
        } else if newPlan.yokoku > 0 {
            let level = newPlan.yokoku
            run { game in
                await game.wait(0.12)
                game.showYokoku(level)
            }
        }
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

        if i == 1, let reach = plan.reach {
            stopsEnabledAt = now.addingTimeInterval(landing + 0.7)
            run { game in
                await game.wait(landing * 0.6)
                game.announceReach(reach)
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

    /// リールの上をタップしたとき(レバー / 停止 / タメのスキップ / PUSH)
    func tapReels() {
        switch phase {
        case .idle: pullLever()
        case .spinning: pressStop()
        case .buildUp: skipBuildUp()
        case .awaitingPush: tapPush()
        case .presenting: break
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

    /// 裏ボタン: 赤以上のタメ中にリールを叩くと、タメを飛ばして一発で答えを出す
    func skipBuildUp() {
        guard canSkipBuildUp else { return }
        sound.silence()
        haptics.cancelBuildUp()
        sound.play(.push)
        haptics.push(level: 1)
        flash(.white, strength: 0.7)
        reveal()
    }

    func refill() {
        guard needsRefill else { return }
        player.credits += PlayerStore.refillAmount
        player.borrowed += PlayerStore.refillAmount
        sound.play(.coin)
        haptics.coin(0.8)
    }

    /// 席を立つ
    func leave() {
        auto = false
        sound.stopMusic()
        haptics.stopHeartbeat()
        hall.update(machineNumber) { $0.occupant = nil }
    }

    /// 答え合わせ(今日のこの台の設定を見る)
    func revealSetting() {
        hall.update(machineNumber) { $0.revealed = true }
    }

    func appBecameActive() {
        haptics.wake()
        switch mode {
        case .bonus: sound.playMusic(.bonus)
        case .rush(_, let isSuper): sound.playMusic(isSuper ? .superRush : .rush)
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
        currentReach = reach
        // 寸止め(半コマ上で粘る)は赤以上だけ。青・緑はリールが回ったままサクッと答えを出す
        holdingThird = reach.color.usesHold
        if holdingThird {
            let missCenter: SlotSymbol = reach.wins ? .replay : plan.centers[2]
            heldIndex = reels[2].hold(at: now, symbol: reach.symbol, missCenter: missCenter)
        }

        // ① 静寂: 音も振動も一瞬すべて消して、画面を暗くする
        haptics.stopHeartbeat()
        sound.silence()
        sound.play(.cut, volume: 0.8)
        haptics.freeze()
        let silence = holdingThird ? 0.28 : 0.12
        withAnimation(.easeOut(duration: 0.12)) { dim = holdingThird ? 0.6 : 0.35 }

        run { game in
            await game.wait(silence)
            await game.runBuildUp(reach)
        }
    }

    /// ② タメ: 色が 青 → … → 答えの色 へ段階的に上がり、音と振動がせり上がる
    private func runBuildUp(_ reach: ReachPlan) async {
        guard phase == .buildUp else { return } // 静寂の間にスキップされた
        let seconds = reach.color.buildUpSeconds
        let steps = reach.color.rawValue + 1
        buildUpStart = Date()
        buildUpDuration = seconds
        withAnimation(.easeOut(duration: 0.25)) { dim = 0.25 }
        withAnimation(.easeIn(duration: seconds)) { zoom = reach.color.usesHold ? 1.08 : 1.03 }
        sound.play(.riser(tenths: Int((seconds * 10).rounded())), volume: 0.9)
        haptics.buildUp(seconds: seconds)

        for k in 0..<steps {
            guard phase == .buildUp else { return }
            let color = ExpectColor(rawValue: k) ?? .blue
            aura = color
            if player.see(color), player.seenColors.count == ExpectColor.allCases.count {
                award(.allColors)
            }
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
        guard phase == .buildUp else { return }

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
        buildUpStart = nil
        let now = Date()
        let duration = holdingThird
            ? reels[2].settle(at: now, heldIndex: heldIndex, wins: reach.wins)
            : reels[2].stop(at: now, center: plan.centers[2])
        shakeBase = 0
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            zoom = 1
            dim = 0
        }
        if !holdingThird {
            sound.play(.stop, volume: 0.9)
            haptics.stop(strong: true)
        }
        let settleWait = duration * (holdingThird ? 0.9 : 0.6)
        run { game in
            await game.wait(settleWait)
            game.sound.restoreMusic()
            if reach.wins {
                await game.celebrate(plan.startsBonus ?? .big)
            } else {
                game.missAfterReach(reach)
                await game.finishSpin(plan)
            }
        }
    }

    private func missAfterReach(_ reach: ReachPlan) {
        haptics.lose()
        reachActive = false
        aura = nil
        guard reach.color.usesHold else {
            // 青・緑のハズレはあっさり
            sound.play(.lose, volume: 0.35)
            return
        }
        sound.play(.lose)
        withAnimation(.easeOut(duration: 0.2)) { desaturate = true }
        showSlam("あと1コマ…", style: .info, hold: 1.1)
        run { game in
            await game.wait(0.9)
            withAnimation(.easeInOut(duration: 0.6)) { game.desaturate = false }
        }
    }

    // MARK: - ロングフリーズ

    /// 暗転 → 無音 → 鼓動 → 逆回転 → 7 がひとつずつ止まる → BIG + SUPER RUSH
    private func runFreeze() async {
        freezeActive = true
        player.freezeCount += 1
        award(.freeze)
        superAfterBonus = true

        // 暗転。すべての音と振動が止まり、操作もできない
        sound.silence()
        sound.stopMusic()
        haptics.stopHeartbeat()
        sound.play(.cut)
        haptics.freezeHit()
        withAnimation(.easeIn(duration: 0.08)) { dim = 1 }
        await wait(1.8)

        for i in 0..<3 {
            sound.play(.heartbeat, volume: 0.7 + 0.15 * Float(i))
            haptics.push(level: 0.5 + 0.25 * Double(i))
            flash(.color(.red), strength: 0.1 + 0.08 * Double(i))
            await wait(0.8)
        }

        // 逆回転
        let now = Date()
        for i in 0..<3 {
            reels[i].startReverse(at: now.addingTimeInterval(Double(i) * 0.15))
        }
        withAnimation(.easeOut(duration: 0.8)) { dim = 0.3 }
        lampLit = true
        sound.play(.kyuin)
        haptics.kyuin()
        flash(.rainbow, strength: 0.9)
        particles.burst(.ember, count: 160, at: UnitPoint(x: 0.5, y: 0.42))
        showSlam("KOKORO FREEZE", subtitle: "BIG + SUPER RUSH 確定", style: .bonus, hold: 2.6)
        await wait(3.0)

        for i in 0..<3 {
            reels[i].stopReverse(at: Date(), center: .seven)
            sound.play(.stop)
            haptics.stop(strong: true)
            flash(.white, strength: 0.35)
            kick(8 + 4 * Double(i), duration: 0.3)
            await wait(0.6)
        }
        withAnimation(.easeOut(duration: 0.3)) { dim = 0 }
        freezeActive = false
        await celebrate(.big)
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
            // RUSH 中のスイカは 1/3 で SUPER に昇格
            if role == .watermelon, case .rush(let left, false) = mode, Int.random(in: 0..<3) == 0 {
                await promoteToSuper(left: left)
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
            player.credits += 1
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
        if plan?.anomaly != nil { award(.anomalyWin) }

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
        let fromRush = mode.isRush
        let wasSuper = mode.isSuperRush
        let before = machineData
        if fromRush {
            rushChain += 1
        } else {
            rushChain = 1
            rushTotal = 0
        }
        // RUSH 中のボーナス、または BIG なら終了後に RUSH
        rushAfterBonus = fromRush || kind == .big
        if wasSuper || (fromRush && rushChain >= SlotLottery.superChain) { superAfterBonus = true }

        if hitGames == 1 && before.bonusCount > 0 { award(.oneGameRenchan) }
        if rushChain >= 5 { award(.chain5) }
        if rushChain >= 10 { award(.chain10) }
        player.bestChain = max(player.bestChain, rushChain)
        player.lifetimeBonuses += 1

        let chain = rushChain
        hall.update(machineNumber) { d in
            d.history.insert(MachineData.Record(id: d.bonusCount + 1, kind: kind, games: d.gamesSinceBonus), at: 0)
            if d.history.count > 30 { d.history.removeLast() }
            d.gamesSinceBonus = 0
            if kind == .big { d.bigCount += 1 } else { d.regCount += 1 }
            d.maxChain = max(d.maxChain, chain)
        }

        pendingBonus = nil
        zoneGamesLeft = 0
        reachActive = false
        rays = false
        aura = nil
        buildUpStart = nil
        bonusGained = 0
        mode = .bonus(kind, gamesLeft: kind.games)
        sound.playMusic(.bonus)
        phase = .idle
        nextAutoAction = Date().addingTimeInterval(0.6)
    }

    private func endBonus(_ kind: BonusKind) async {
        phase = .presenting
        sound.stopMusic()
        sound.play(.bonusEnd)
        haptics.smallWin()
        lampLit = false
        rushTotal += bonusGained

        // 設定示唆
        let hint = SlotLottery.settingHint(for: setting.level, using: &rng)
        hall.update(machineNumber) { $0.hints.append(hint) }
        if hint == .rainbow { award(.rainbowHint) }
        showSlam("BONUS END", subtitle: "+\(bonusGained)枚   示唆 \(hint.emoji)", style: .info, hold: 1.8)
        switch hint {
        case .white: break
        case .blue: flash(.color(.blue), strength: 0.35)
        case .red: flash(.color(.red), strength: 0.35)
        case .gold: flash(.color(.gold), strength: 0.45)
        case .rainbow: flash(.rainbow, strength: 0.6)
        }
        await wait(1.9)

        if rushAfterBonus {
            let isSuper = superAfterBonus
            rushAfterBonus = false
            superAfterBonus = false
            mode = .rush(gamesLeft: SlotLottery.rushGames, isSuper: isSuper)
            if isSuper { award(.superRush) }
            sound.play(.rushStart)
            sound.playMusic(isSuper ? .superRush : .rush)
            haptics.fanfare()
            flash(.rainbow, strength: 0.8)
            kick(12, duration: 0.6)
            particles.burst(.confetti, count: isSuper ? 320 : 220, at: UnitPoint(x: 0.5, y: 0.4), power: 1)
            let chain = rushChain >= 2 ? "\(rushChain)連中!" : "連チャンのチャンス!"
            showSlam(isSuper ? "SUPER KOKORO RUSH" : "KOKORO RUSH",
                     subtitle: isSuper ? "継続 約80%  \(chain)" : chain, style: .bonus, hold: 2.0)
            await wait(1.8)
        } else {
            // 通常時の REG: RUSH には入らない
            mode = .normal
            rushChain = 0
            rushTotal = 0
        }
    }

    /// RUSH 中のスイカで SUPER に昇格
    private func promoteToSuper(left: Int) async {
        mode = .rush(gamesLeft: left, isSuper: true)
        award(.superRush)
        sound.play(.kyuin)
        sound.playMusic(.superRush)
        haptics.kyuin()
        flash(.rainbow, strength: 0.9)
        kick(12, duration: 0.5)
        particles.burst(.spark, count: 150, at: UnitPoint(x: 0.5, y: 0.3), power: 1.2)
        showSlam("SUPER 昇格!!", subtitle: "継続 約80%", style: .bonus, hold: 1.6)
        await wait(1.6)
    }

    private func endRush() {
        let chain = rushChain
        if chain >= 2 {
            showSlam("RUSH 終了", subtitle: "\(chain)連  +\(rushTotal)枚", style: .info, hold: 2.2)
        }
        if rushTotal >= 1000 { award(.oneShot1000) }
        player.bestRushTotal = max(player.bestRushTotal, rushTotal)
        mode = .normal
        rushChain = 0
        rushTotal = 0
        sound.stopMusic()
        if chain <= 1 {
            // 駆け抜け救済: しばらくボーナス確率 2 倍
            zoneGamesLeft = SlotLottery.zoneGames
            sound.play(.yokoku(3))
            haptics.step(2)
            flash(.color(.gold), strength: 0.5)
            showSlam("CHANCE ZONE", subtitle: "\(SlotLottery.zoneGames)G ボーナス確率 2 倍", style: .bonus, hold: 1.8)
        }
    }

    private func finishSpin(_ plan: SpinPlan) async {
        haptics.stopHeartbeat()
        reachActive = false
        buttonHint = nil
        aura = nil
        shakeBase = 0
        buildUpStart = nil
        currentReach = nil

        switch mode {
        case .bonus(let kind, let left):
            if left <= 1 {
                await endBonus(kind)
            } else {
                mode = .bonus(kind, gamesLeft: left - 1)
            }
        case .rush(let left, let isSuper):
            if plan.isBonusHit || pendingBonus != nil { break }
            if left <= 1 {
                endRush()
            } else {
                mode = .rush(gamesLeft: left - 1, isSuper: isSuper)
            }
        case .normal:
            if zoneGamesLeft > 0 && !plan.isBonusHit && pendingBonus == nil {
                zoneGamesLeft -= 1
                if zoneGamesLeft == 0 {
                    showSlam("ZONE 終了", style: .info, hold: 0.9)
                }
            }
        }
        phase = .idle
        nextAutoAction = Date().addingTimeInterval(0.45)
    }

    // MARK: - 予告・実績

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

    private func checkSpinAchievements() {
        if player.lifetimeSpins >= 1000 { award(.spins1000) }
        if player.lifetimeSpins >= 10000 { award(.spins10000) }
    }

    /// 実績を解除して、初めてならお知らせを出す
    private func award(_ achievement: Achievement) {
        guard player.unlock(achievement) else { return }
        toastCounter += 1
        toast = AchievementToast(id: toastCounter, achievement: achievement)
        run { game in
            // 演出の音とかぶらないように少し遅らせる
            await game.wait(0.6)
            game.sound.play(.achievement, volume: 0.7)
            game.haptics.smallWin()
        }
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
