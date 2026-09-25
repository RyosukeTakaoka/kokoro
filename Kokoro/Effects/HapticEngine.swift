import CoreHaptics
import Foundation

/// 振動の演出。Taptic Engine がある iPhone では CoreHaptics で細かく作り込み、
/// 無い端末(iPad など)では何もしない。呼び出しはメインスレッドから。
final class HapticEngine {
    static let shared = HapticEngine()

    var isEnabled = true {
        didSet { if !isEnabled { stopHeartbeat() } }
    }

    let supportsHaptics: Bool
    private var engine: CHHapticEngine?
    private var heartbeatPlayer: CHHapticAdvancedPatternPlayer?
    /// タメの振動(スキップしたときに止めるため覚えておく)
    private var buildUpPlayer: CHHapticPatternPlayer?

    private init() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        makeEngine()
    }

    private func makeEngine() {
        guard supportsHaptics else { return }
        do {
            let e = try CHHapticEngine()
            e.playsHapticsOnly = true
            e.isAutoShutdownEnabled = false
            e.stoppedHandler = { [weak self] _ in
                DispatchQueue.main.async { self?.heartbeatPlayer = nil }
            }
            e.resetHandler = { [weak self] in
                DispatchQueue.main.async {
                    self?.heartbeatPlayer = nil
                    try? self?.engine?.start()
                }
            }
            try e.start()
            engine = e
        } catch {
            engine = nil
        }
    }

    /// アプリが前面に戻ったときなどに呼ぶ
    func wake() {
        guard supportsHaptics else { return }
        if engine == nil { makeEngine() }
        try? engine?.start()
    }

    // MARK: - 部品

    private func tap(_ intensity: Double, _ sharpness: Double, at time: Double) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(max(0, min(1, intensity)))),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(max(0, min(1, sharpness)))),
        ], relativeTime: time)
    }

    private func buzz(_ intensity: Double, _ sharpness: Double, at time: Double, for duration: Double) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(max(0, min(1, intensity)))),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(max(0, min(1, sharpness)))),
        ], relativeTime: time, duration: duration)
    }

    private func curve(_ id: CHHapticDynamicParameter.ID, _ points: [(Double, Double)],
                       at time: Double = 0) -> CHHapticParameterCurve {
        CHHapticParameterCurve(parameterID: id,
                               controlPoints: points.map {
                                   CHHapticParameterCurve.ControlPoint(relativeTime: $0.0, value: Float($0.1))
                               },
                               relativeTime: time)
    }

    @discardableResult
    private func play(_ events: [CHHapticEvent], curves: [CHHapticParameterCurve] = []) -> CHHapticPatternPlayer? {
        guard isEnabled, supportsHaptics else { return nil }
        if engine == nil { makeEngine() }
        guard let engine else { return nil }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return player
        } catch {
            // エンジンが止まっていたら起こしてもう 1 回だけ試す
            try? engine.start()
            if let pattern = try? CHHapticPattern(events: events, parameterCurves: curves),
               let player = try? engine.makePlayer(with: pattern) {
                try? player.start(atTime: CHHapticTimeImmediate)
                return player
            }
            return nil
        }
    }

    // MARK: - 演出ごとの振動

    /// レバー: ガツンと 1 発 + 短いうなり
    func lever() {
        play([tap(1, 0.75, at: 0), buzz(0.5, 0.2, at: 0.01, for: 0.07)])
    }

    /// 違和感: レバーの振動が「トトン」と一瞬ズレる
    func leverStutter() {
        play([tap(1, 0.75, at: 0), tap(0.55, 0.9, at: 0.085), buzz(0.5, 0.2, at: 0.01, for: 0.07)])
    }

    /// フリーズ: 重く低い 1 発(暗転の瞬間)
    func freezeHit() {
        play([tap(1, 0.05, at: 0), buzz(1, 0, at: 0, for: 0.6)],
             curves: [curve(.hapticIntensityControl, [(0, 1), (0.6, 0)])])
    }

    /// リール停止: 硬く短く
    func stop(strong: Bool = false) {
        play([tap(strong ? 1 : 0.85, strong ? 1 : 0.9, at: 0)])
    }

    /// リーチ成立: ダダダッ + うなり
    func reach() {
        play([tap(0.6, 0.6, at: 0), tap(0.8, 0.7, at: 0.1), tap(1, 0.9, at: 0.2),
              buzz(0.7, 0.3, at: 0.2, for: 0.35)],
             curves: [curve(.hapticIntensityControl, [(0, 1), (0.35, 0)], at: 0.2)])
    }

    /// 静寂に入る瞬間。ごく弱く「カチッ」とだけ。
    func freeze() {
        play([tap(0.35, 1, at: 0)])
    }

    /// タメ: `seconds` のあいだ、叩く間隔が詰まりながら強く鋭くなっていく。最後は無振動(静寂)。
    func buildUp(seconds: Double) {
        var events: [CHHapticEvent] = []
        let body = seconds - 0.08
        var t = 0.0
        while t < body {
            let p = t / body
            events.append(tap(0.25 + 0.75 * p * p, 0.2 + 0.8 * p, at: t))
            // 最初は 0.2 秒おき、最後は 0.035 秒おき
            t += 0.2 - 0.165 * pow(p, 0.7)
        }
        // 下に敷く連続振動も少しずつ大きく
        events.append(buzz(1, 0.2, at: 0, for: body))
        let rise = curve(.hapticIntensityControl, [(0, 0.08), (body * 0.5, 0.25), (body * 0.9, 0.7), (body, 0.9)])
        buildUpPlayer = play(events, curves: [rise])
    }

    /// タメをスキップしたときに、流れているタメの振動を止める
    func cancelBuildUp() {
        try? buildUpPlayer?.stop(atTime: CHHapticTimeImmediate)
        buildUpPlayer = nil
    }

    /// 色が 1 段上がったとき
    func step(_ level: Int) {
        let p = Double(level) / 4
        play([tap(0.6 + 0.4 * p, 0.5 + 0.5 * p, at: 0), buzz(0.4 + 0.5 * p, 0.3, at: 0, for: 0.08)])
    }

    /// 大当たりの爆発: 最大強度の連続振動 → 地鳴りのような連打が 1.6 秒かけて消える
    func explosion() {
        var events: [CHHapticEvent] = [tap(1, 1, at: 0), buzz(1, 0.6, at: 0, for: 0.45)]
        var t = 0.45
        var i = 0
        while t < 2.0 {
            let fade = 1 - (t - 0.45) / 1.55
            events.append(tap(0.4 + 0.6 * fade, i % 2 == 0 ? 0.9 : 0.3, at: t))
            t += 0.055
            i += 1
        }
        events.append(buzz(0.6, 0.1, at: 0.45, for: 1.5))
        play(events, curves: [curve(.hapticIntensityControl, [(0, 1), (1.5, 0)], at: 0.45)])
    }

    /// ファンファーレに合わせたリズム
    func fanfare() {
        let beats = [0.0, 0.11, 0.22, 0.33, 0.60, 0.71, 0.84]
        var events = beats.enumerated().map { i, t in tap(0.6 + 0.06 * Double(i), 0.8, at: t) }
        events.append(buzz(0.8, 0.5, at: 0.84, for: 0.9))
        play(events, curves: [curve(.hapticIntensityControl, [(0, 1), (0.9, 0)], at: 0.84)])
    }

    /// キュイーン: 鋭さがせり上がる連続振動
    func kyuin() {
        play([tap(1, 1, at: 0), buzz(1, 0.1, at: 0, for: 0.9)],
             curves: [curve(.hapticSharpnessControl, [(0, -0.5), (0.26, 0.5), (0.9, 0.5)]),
                      curve(.hapticIntensityControl, [(0, 0.7), (0.3, 1), (0.6, 1), (0.9, 0)])])
    }

    /// ハズレ: 鈍い 2 回
    func lose() {
        play([tap(0.55, 0.1, at: 0), tap(0.4, 0.05, at: 0.2)])
    }

    /// 小役・メダル 1 枚ぶん
    func coin(_ strength: Double = 0.4) {
        play([tap(strength, 1, at: 0)])
    }

    /// 小役が揃った: 軽やかに 3 回
    func smallWin() {
        play([tap(0.5, 0.9, at: 0), tap(0.6, 0.95, at: 0.06), tap(0.75, 1, at: 0.12)])
    }

    /// PUSH を促す鼓動 / 連打 1 回ぶん。level は 0〜1
    func push(level: Double) {
        play([tap(0.5 + 0.5 * level, 0.4 + 0.6 * level, at: 0), buzz(0.3 + 0.6 * level, 0.2, at: 0, for: 0.05)])
    }

    // MARK: - ループする鼓動(リーチ中)

    /// ドクン…ドクン…。`rate` は 1 秒あたりの拍数
    func startHeartbeat(rate: Double = 1.4) {
        guard isEnabled, supportsHaptics, let engine else { return }
        stopHeartbeat()
        let period = 1 / rate
        let events = [tap(0.9, 0.15, at: 0), buzz(0.5, 0.05, at: 0, for: 0.08),
                      tap(0.6, 0.1, at: 0.17)]
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            player.loopEnd = period
            try player.start(atTime: CHHapticTimeImmediate)
            heartbeatPlayer = player
        } catch {
            heartbeatPlayer = nil
        }
    }

    func stopHeartbeat() {
        try? heartbeatPlayer?.stop(atTime: CHHapticTimeImmediate)
        heartbeatPlayer = nil
    }
}
