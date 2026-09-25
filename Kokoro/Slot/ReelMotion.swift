import Foundation

/// 1 本のリールの動き。
///
/// 位置 `position` は「中段に来ているコマ番号」で、回るほど増える(巻き戻らない)。
/// コマ `i` は中段から `(position - i)` コマぶん下に描かれるので、図柄は上から下へ流れる。
/// 時刻を渡すと位置が決まる純粋な関数にしてあり、画面は TimelineView で毎フレーム描き直すだけ。
struct ReelMotion {
    enum State {
        case stopped(position: Double)
        /// 加速しながら回る
        case spinning(start: Date, from: Double)
        /// 目標のコマへ減速して止まる(最後に少しだけ行き過ぎて戻る)
        case stopping(start: Date, from: Double, to: Double, duration: Double)
        /// リーチの最後の 1 本: 図柄が中段の半コマ手前でじわじわ震えながら粘る
        case holding(start: Date, from: Double, hold: Double)
        /// 粘っていた位置から答えの位置へ動く
        case settling(start: Date, from: Double, to: Double, duration: Double)
        /// フリーズ演出: ゆっくり逆回転(図柄が下から上へ)
        case reversing(start: Date, from: Double)
    }

    static let reverseSpeed = 7.0

    /// 1 秒に流れるコマ数(実機の 80 回転/分 ≒ 28 コマ/秒くらい)
    static let spinSpeed = 30.0
    static let spinUpTime = 0.12
    static let bounceTime = 0.16
    static let bounceDepth = 0.07

    var state: State = .stopped(position: 0)
    /// 止める位置の図柄を上書きする(抽選結果に合わせて差し替える)
    var overrides: [Int: SlotSymbol] = [:]

    func symbol(reel: Int, index: Int) -> SlotSymbol {
        overrides[index] ?? ReelStrip.symbol(reel: reel, index: index)
    }

    var isStopped: Bool {
        if case .stopped = state { return true }
        return false
    }

    // MARK: 位置

    func position(at now: Date) -> Double {
        switch state {
        case .stopped(let p):
            return p
        case .spinning(let start, let from):
            let t = max(0, now.timeIntervalSince(start))
            let tau = Self.spinUpTime
            // v * (t - tau(1 - e^{-t/tau})): 0 から滑らかに最高速へ
            return from + Self.spinSpeed * (t - tau * (1 - exp(-t / tau)))
        case .stopping(let start, let from, let to, let duration):
            let t = max(0, now.timeIntervalSince(start))
            if t < duration {
                let x = t / duration
                let eased = 1 - (1 - x) * (1 - x)
                return from + (to - from) * eased
            }
            // 着地後の小さなバウンド(少し行き過ぎて戻る)
            let b = min(1, (t - duration) / Self.bounceTime)
            return to + Self.bounceDepth * sin(.pi * b) * (1 - b)
        case .holding(let start, let from, let hold):
            let t = max(0, now.timeIntervalSince(start))
            // 最初の 0.4 秒で急ブレーキして hold に吸い付き、あとはじわじわ這う + 震え
            let brake = 0.4
            if t < brake {
                let x = t / brake
                return from + (hold - from) * (1 - pow(1 - x, 3))
            }
            let creep = min(0.2, (t - brake) * 0.07)
            let tremble = 0.018 * sin(t * 71) * min(1, (t - brake) / 1.5)
            return hold + creep + tremble
        case .settling(let start, let from, let to, let duration):
            let t = max(0, now.timeIntervalSince(start))
            if t < duration {
                let x = t / duration
                // 溜めてから一気に落ちる(ease-in)
                let eased = x * x * x
                return from + (to - from) * eased
            }
            let b = min(1, (t - duration) / (Self.bounceTime * 1.4))
            return to + Self.bounceDepth * 2.2 * sin(.pi * b) * (1 - b)
        case .reversing(let start, let from):
            let t = max(0, now.timeIntervalSince(start))
            // 0.8 秒かけてじわっと逆向きに加速する
            let distance = t < 0.8 ? t * t / 1.6 : t - 0.4
            return from - Self.reverseSpeed * distance
        }
    }

    /// 回っている速さ(コマ/秒)。ブラーの強さに使う。
    func speed(at now: Date) -> Double {
        switch state {
        case .spinning(let start, _):
            let t = max(0, now.timeIntervalSince(start))
            return Self.spinSpeed * (1 - exp(-t / Self.spinUpTime))
        case .stopping(let start, _, _, let duration):
            let t = max(0, now.timeIntervalSince(start))
            return t < duration ? Self.spinSpeed * (1 - t / duration) : 0
        case .reversing:
            return Self.reverseSpeed
        default:
            return 0
        }
    }

    // MARK: 操作

    mutating func startSpin(at now: Date) {
        let p = position(at: now)
        // 前回の上書きは画面から外れたら要らないが、見えている間は残す
        overrides = overrides.filter { abs(Double($0.key) - p) < 3 }
        state = .spinning(start: now, from: p)
    }

    /// 中段に `center` が来るように止める。上下の段は `above` / `below`(nil なら元の並び)。
    /// 返り値は止まり終わるまでの秒数。
    @discardableResult
    mutating func stop(at now: Date, center: SlotSymbol, above: SlotSymbol? = nil,
                       below: SlotSymbol? = nil) -> Double {
        let p = position(at: now)
        // 見えている範囲(±1.5 コマ)の外で差し替えるため、4 コマ以上先で止める
        let target = Int(floor(p)) + 4
        overrides[target] = center
        overrides[target + 1] = above
        overrides[target - 1] = below
        let distance = Double(target) - p
        // ease-out の初速 = 2 * 距離 / 時間 を回転速度に合わせる
        let duration = 2 * distance / Self.spinSpeed
        state = .stopping(start: now, from: p, to: Double(target), duration: duration)
        return duration + Self.bounceTime
    }

    /// フリーズ演出の逆回転を始める
    mutating func startReverse(at now: Date) {
        state = .reversing(start: now, from: position(at: now))
    }

    /// 逆回転しているリールを `center` で止める(図柄は下から上へ流れて止まる)
    @discardableResult
    mutating func stopReverse(at now: Date, center: SlotSymbol) -> Double {
        let p = position(at: now)
        let target = Int(ceil(p)) - 3
        overrides[target] = center
        overrides[target + 1] = nil
        overrides[target - 1] = nil
        let duration = 0.35
        state = .stopping(start: now, from: p, to: Double(target), duration: duration)
        return duration + Self.bounceTime
    }

    /// リーチの最後の 1 本。`symbol` が中段の半コマ上で粘るように止める。
    /// `missCenter` はハズレたときに中段へ来る図柄(粘っている間は上段の端に見えている)。
    /// 返り値は粘っている図柄のコマ番号。
    mutating func hold(at now: Date, symbol: SlotSymbol, missCenter: SlotSymbol) -> Int {
        let p = position(at: now)
        let target = Int(floor(p)) + 5
        overrides[target] = symbol
        overrides[target + 1] = missCenter
        overrides[target + 2] = .bell
        overrides[target - 1] = .cherry
        state = .holding(start: now, from: p, hold: Double(target) - 0.62)
        return target
    }

    /// 粘っていたリールを答えの位置へ動かす。
    /// 当たり: 粘っていた図柄が中段にストンと落ちる。ハズレ: 中段を通り過ぎて 1 コマ下で止まる。
    @discardableResult
    mutating func settle(at now: Date, heldIndex: Int, wins: Bool) -> Double {
        let p = position(at: now)
        if wins {
            state = .settling(start: now, from: p, to: Double(heldIndex), duration: 0.16)
            return 0.16
        }
        // 通り過ぎる: 粘っていた図柄は下段へ、中段には hold のときに決めた missCenter
        state = .settling(start: now, from: p, to: Double(heldIndex + 1), duration: 0.42)
        return 0.42
    }

    /// 止まったときの位置(中段のコマ番号)
    func restingIndex(at now: Date) -> Int {
        Int(position(at: now).rounded())
    }
}
