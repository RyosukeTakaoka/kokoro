import Foundation

/// 効果音と BGM をその場で合成する(音声ファイルを持たない)。
/// どれも 44.1kHz モノラルの Float 配列を返すだけの純粋な関数。
enum SoundSynth {
    static let rate = 44_100.0

    enum Wave {
        case sine
        case square
        case saw
        case triangle
        case noise
    }

    // MARK: - 部品

    static func silence(_ seconds: Double) -> [Float] {
        Array(repeating: 0, count: Int(seconds * rate))
    }

    static func midi(_ note: Double) -> Double {
        440 * pow(2, (note - 69) / 12)
    }

    /// `out` の `start` 秒目から 1 音を足し込む。
    /// `freq` と `env` は音の頭からの経過秒を受け取る。`wrap` なら末尾からはみ出た分を先頭へ回す(ループ用)。
    static func add(_ out: inout [Float], at start: Double, duration: Double, wave: Wave, amp: Double,
                    wrap: Bool = false, freq: (Double) -> Double, env: (Double) -> Double) {
        let count = out.count
        guard count > 0 else { return }
        let first = Int(start * rate)
        let frames = Int(duration * rate)
        var phase = 0.0
        var seed: UInt32 = 0x9E37_79B9 &+ UInt32(truncatingIfNeeded: first)
        for n in 0..<frames {
            var index = first + n
            if index >= count {
                guard wrap else { break }
                index %= count
            }
            let t = Double(n) / rate
            let f = freq(t)
            phase += f / rate
            phase -= floor(phase)
            let v: Double
            switch wave {
            case .sine:
                v = sin(2 * .pi * phase)
            case .square:
                v = phase < 0.5 ? 1 : -1
            case .saw:
                v = 2 * phase - 1
            case .triangle:
                v = 4 * abs(phase - 0.5) - 1
            case .noise:
                // xorshift で軽い白色雑音
                seed ^= seed << 13
                seed ^= seed >> 17
                seed ^= seed << 5
                v = Double(seed) / Double(UInt32.max) * 2 - 1
            }
            out[index] += Float(v * amp * env(t))
        }
    }

    static func decay(_ tau: Double, attack: Double = 0.003) -> (Double) -> Double {
        { t in
            let a = attack > 0 ? min(1, t / attack) : 1
            return a * exp(-t / tau)
        }
    }

    /// 立ち上がり → 持続 → 余韻 の包絡線
    static func adsr(attack: Double, decay: Double, sustain: Double, length: Double,
                     release: Double) -> (Double) -> Double {
        { t in
            if t < attack { return t / attack }
            if t < attack + decay { return 1 - (1 - sustain) * (t - attack) / decay }
            if t < length { return sustain }
            return max(0, sustain * (1 - (t - length) / release))
        }
    }

    /// 音割れしないように柔らかく丸める
    static func finish(_ out: [Float], gain: Float = 1) -> [Float] {
        out.map { tanhf($0 * gain) }
    }

    // MARK: - 効果音

    /// レバーを叩いた音(ガコッ)
    /// pitch > 1 で少し高い(違和感用)
    static func lever(pitch: Double = 1) -> [Float] {
        var o = silence(0.2)
        add(&o, at: 0, duration: 0.04, wave: .noise, amp: 0.6, freq: { _ in 0 }, env: decay(0.008, attack: 0))
        add(&o, at: 0, duration: 0.18, wave: .sine, amp: 0.95,
            freq: { t in (100 - 45 * min(1, t / 0.1)) * pitch }, env: decay(0.05))
        add(&o, at: 0.005, duration: 0.015, wave: .square, amp: 0.15, freq: { _ in 2200 * pitch }, env: decay(0.004))
        return finish(o)
    }

    /// リールが止まる音(ドッ)
    static func stop() -> [Float] {
        var o = silence(0.16)
        add(&o, at: 0, duration: 0.14, wave: .sine, amp: 0.95,
            freq: { t in 175 - 90 * min(1, t / 0.08) }, env: decay(0.035))
        add(&o, at: 0, duration: 0.015, wave: .noise, amp: 0.5, freq: { _ in 0 }, env: decay(0.003, attack: 0))
        add(&o, at: 0, duration: 0.03, wave: .square, amp: 0.12, freq: { _ in 880 }, env: decay(0.006))
        return finish(o)
    }

    /// リーチ成立(ピロピロピロ → ジャーン)
    static func reach() -> [Float] {
        var o = silence(1.1)
        let notes = [1318.5, 1760.0]
        for i in 0..<8 {
            add(&o, at: Double(i) * 0.06, duration: 0.058, wave: .square, amp: 0.22,
                freq: { _ in notes[i % 2] }, env: decay(0.05))
        }
        for f in [880.0, 1108.7, 1318.5, 1760.0] {
            add(&o, at: 0.5, duration: 0.6, wave: .saw, amp: 0.1,
                freq: { t in f * (1 + 0.006 * sin(t * 2 * .pi * 6)) }, env: decay(0.25, attack: 0.01))
        }
        add(&o, at: 0.5, duration: 0.4, wave: .sine, amp: 0.8, freq: { t in 90 - 40 * min(1, t / 0.2) },
            env: decay(0.12))
        return finish(o)
    }

    /// タメで色が上がるたびの音。level が上がるほど高い。
    static func step(_ level: Int) -> [Float] {
        var o = silence(0.5)
        let semis = [0.0, 3, 5, 7, 12, 15]
        let f0 = 523.25 * pow(2, semis[min(level, semis.count - 1)] / 12)
        add(&o, at: 0, duration: 0.45, wave: .sine, amp: 0.45, freq: { _ in f0 }, env: decay(0.16))
        add(&o, at: 0, duration: 0.3, wave: .sine, amp: 0.15, freq: { _ in f0 * 2 }, env: decay(0.1))
        add(&o, at: 0, duration: 0.25, wave: .triangle, amp: 0.12, freq: { _ in f0 * 3 }, env: decay(0.07))
        add(&o, at: 0, duration: 0.18, wave: .sine, amp: 0.7, freq: { t in 90 - 40 * min(1, t / 0.1) },
            env: decay(0.05))
        add(&o, at: 0, duration: 0.12, wave: .noise, amp: 0.12, freq: { _ in 0 }, env: decay(0.03, attack: 0))
        return finish(o)
    }

    /// タメ中にせり上がるうなり。最後の 60ms は無音にして、爆発との落差を作る。
    static func riser(_ seconds: Double) -> [Float] {
        var o = silence(seconds)
        let body = seconds - 0.06
        let sampleRate = rate
        var tremPhase = 0.0
        let shape: (Double) -> Double = { t in
            let x = min(1, t / body)
            guard t < body else { return 0 }
            tremPhase += (6 + 34 * x) / sampleRate
            let trem = 0.6 + 0.4 * sin(2 * .pi * tremPhase)
            return (0.12 + 0.88 * x * x) * trem
        }
        let sweep: (Double) -> Double = { t in 170 * pow(1600.0 / 170, pow(min(1, t / body), 1.4)) }
        add(&o, at: 0, duration: seconds, wave: .saw, amp: 0.2, freq: sweep, env: shape)
        tremPhase = 0
        add(&o, at: 0, duration: seconds, wave: .sine, amp: 0.3, freq: sweep, env: shape)
        tremPhase = 0
        add(&o, at: 0, duration: seconds, wave: .sine, amp: 0.12, freq: { t in sweep(t) * 1.5 }, env: shape)
        add(&o, at: 0, duration: seconds, wave: .noise, amp: 0.14, freq: { _ in 0 },
            env: { t in t < body ? pow(min(1, t / body), 3) : 0 })
        return finish(o)
    }

    /// 告知ランプが点く音(キュイーン)
    static func kyuin() -> [Float] {
        var o = silence(1.05)
        let freq: (Double) -> Double = { t in
            if t < 0.26 {
                return 650 * pow(2900.0 / 650, pow(t / 0.26, 0.8))
            }
            return 2900 + 45 * sin((t - 0.26) * 2 * .pi * 7.5)
        }
        let env: (Double) -> Double = { t in
            let a = min(1, t / 0.015)
            let r = t > 0.62 ? max(0, 1 - (t - 0.62) / 0.4) : 1
            return a * r
        }
        add(&o, at: 0, duration: 1.05, wave: .sine, amp: 0.5, freq: freq, env: env)
        add(&o, at: 0, duration: 1.05, wave: .sine, amp: 0.14, freq: { t in freq(t) * 2 }, env: env)
        add(&o, at: 0, duration: 1.05, wave: .triangle, amp: 0.08, freq: { t in freq(t) * 0.5 }, env: env)
        return finish(o, gain: 1.2)
    }

    /// 大当たりの爆発音(ドゴォン)
    static func boom() -> [Float] {
        var o = silence(1.8)
        add(&o, at: 0, duration: 1.7, wave: .sine, amp: 1.0,
            freq: { t in 28 + 52 * exp(-t / 0.25) }, env: decay(0.5, attack: 0.002))
        // 低域だけ残した雑音(一次ローパス)
        var noise = silence(1.2)
        add(&noise, at: 0, duration: 1.2, wave: .noise, amp: 1, freq: { _ in 0 }, env: decay(0.3, attack: 0))
        var lp: Float = 0
        for i in 0..<noise.count {
            lp += 0.06 * (noise[i] - lp)
            o[i] += lp * 1.6
        }
        add(&o, at: 0, duration: 0.2, wave: .noise, amp: 0.5, freq: { _ in 0 }, env: decay(0.04, attack: 0))
        return finish(o, gain: 1.4)
    }

    /// 大当たりのファンファーレ
    static func fanfare() -> [Float] {
        var o = silence(2.6)
        let c5 = 523.25, e5 = 659.25, g4 = 392.0, g5 = 783.99, c6 = 1046.5
        let notes: [(Double, Double, Double)] = [
            (g4, 0.00, 0.10), (c5, 0.11, 0.10), (e5, 0.22, 0.10), (g5, 0.33, 0.24),
            (e5, 0.60, 0.10), (g5, 0.71, 0.10), (c6, 0.84, 1.45),
        ]
        for (f, t0, len) in notes {
            let vib: (Double) -> Double = { t in f * (1 + (t > 0.3 ? 0.008 * sin(t * 2 * .pi * 5.5) : 0)) }
            let env = adsr(attack: 0.01, decay: 0.08, sustain: 0.7, length: len, release: 0.12)
            add(&o, at: t0, duration: len + 0.15, wave: .saw, amp: 0.17, freq: vib, env: env)
            add(&o, at: t0, duration: len + 0.15, wave: .square, amp: 0.07, freq: vib, env: env)
        }
        for f in [c5, e5, g5] {
            add(&o, at: 0.84, duration: 1.6, wave: .saw, amp: 0.08, freq: { _ in f },
                env: adsr(attack: 0.02, decay: 0.2, sustain: 0.8, length: 1.3, release: 0.3))
        }
        for t0 in [0.0, 0.33, 0.84, 1.2] {
            add(&o, at: t0, duration: 0.35, wave: .sine, amp: 0.8,
                freq: { t in 95 - 35 * min(1, t / 0.15) }, env: decay(0.12))
        }
        return finish(o, gain: 1.1)
    }

    /// ハズレ(デデーン…)
    static func lose() -> [Float] {
        var o = silence(1.0)
        add(&o, at: 0, duration: 0.16, wave: .triangle, amp: 0.45, freq: { _ in 311.1 }, env: decay(0.2))
        add(&o, at: 0.18, duration: 0.8, wave: .triangle, amp: 0.45,
            freq: { t in 293.7 * pow(0.5, min(1, t / 0.7)) * (1 + 0.02 * sin(t * 2 * .pi * 5)) },
            env: adsr(attack: 0.01, decay: 0.1, sustain: 0.8, length: 0.6, release: 0.2))
        add(&o, at: 0.18, duration: 0.3, wave: .sine, amp: 0.6, freq: { _ in 70 }, env: decay(0.1))
        return finish(o)
    }

    /// メダルの音(チャリン)
    static func coin() -> [Float] {
        var o = silence(0.3)
        add(&o, at: 0, duration: 0.2, wave: .sine, amp: 0.33, freq: { _ in 1975.5 }, env: decay(0.05, attack: 0.001))
        add(&o, at: 0.045, duration: 0.25, wave: .sine, amp: 0.33, freq: { _ in 2637 }, env: decay(0.1, attack: 0.001))
        add(&o, at: 0.045, duration: 0.2, wave: .sine, amp: 0.1, freq: { _ in 3951 }, env: decay(0.06, attack: 0.001))
        return finish(o)
    }

    /// 小役が揃った音
    static func smallWin() -> [Float] {
        var o = silence(0.5)
        for (i, f) in [1046.5, 1318.5, 1568.0, 2093.0].enumerated() {
            add(&o, at: Double(i) * 0.06, duration: 0.3, wave: .triangle, amp: 0.3, freq: { _ in f },
                env: decay(0.12))
        }
        return finish(o)
    }

    /// PUSH ボタンが出る・押した音
    static func push() -> [Float] {
        var o = silence(0.4)
        add(&o, at: 0, duration: 0.35, wave: .sine, amp: 0.95, freq: { t in 70 - 25 * min(1, t / 0.2) },
            env: decay(0.12))
        add(&o, at: 0, duration: 0.05, wave: .square, amp: 0.15, freq: { _ in 1200 }, env: decay(0.02))
        add(&o, at: 0, duration: 0.03, wave: .noise, amp: 0.3, freq: { _ in 0 }, env: decay(0.006, attack: 0))
        return finish(o)
    }

    /// 心臓の鼓動(ドクン)
    static func heartbeat() -> [Float] {
        var o = silence(0.45)
        add(&o, at: 0, duration: 0.2, wave: .sine, amp: 1.0, freq: { _ in 55 }, env: decay(0.07, attack: 0.008))
        add(&o, at: 0.16, duration: 0.2, wave: .sine, amp: 0.75, freq: { _ in 48 }, env: decay(0.06, attack: 0.008))
        return finish(o, gain: 1.3)
    }

    /// 連打のたびの音。level(0〜) が上がるほど半音ずつ高くなる。
    static func tick(_ level: Int) -> [Float] {
        var o = silence(0.12)
        let f = 660 * pow(2, Double(level) / 12)
        add(&o, at: 0, duration: 0.1, wave: .square, amp: 0.2, freq: { _ in f }, env: decay(0.025))
        add(&o, at: 0, duration: 0.1, wave: .sine, amp: 0.3, freq: { _ in f * 2 }, env: decay(0.02))
        return finish(o)
    }

    /// 予告(シャキーン)。level 3 以上は低音も足す。
    static func yokoku(_ level: Int) -> [Float] {
        var o = silence(0.7)
        add(&o, at: 0, duration: 0.14, wave: .sine, amp: 0.25,
            freq: { t in 1200 * pow(4000.0 / 1200, t / 0.14) }, env: decay(0.2, attack: 0.005))
        for f in [3000.0, 4200, 5100, 6300] {
            add(&o, at: 0.1, duration: 0.55, wave: .sine, amp: 0.07, freq: { t in f * (1 + 0.004 * sin(t * 90)) },
                env: decay(0.18))
        }
        if level >= 3 {
            add(&o, at: 0.05, duration: 0.5, wave: .sine, amp: 0.9, freq: { t in 80 - 40 * min(1, t / 0.3) },
                env: decay(0.15))
        }
        return finish(o)
    }

    /// 静寂に入る瞬間の「プツッ」
    static func cut() -> [Float] {
        var o = silence(0.05)
        add(&o, at: 0, duration: 0.012, wave: .noise, amp: 0.35, freq: { _ in 0 }, env: decay(0.003, attack: 0))
        return finish(o)
    }

    /// ボーナス終了・RUSH 突入のジングル
    static func jingle(rising: Bool) -> [Float] {
        var o = silence(1.6)
        let seq: [Double] = rising ? [72, 76, 79, 84, 88, 91, 96] : [84, 79, 76, 72, 76, 79, 84]
        for (i, m) in seq.enumerated() {
            let f = midi(m)
            add(&o, at: Double(i) * 0.08, duration: 0.5, wave: .square, amp: 0.12, freq: { _ in f },
                env: decay(0.12))
            add(&o, at: Double(i) * 0.08, duration: 0.5, wave: .triangle, amp: 0.2, freq: { _ in f },
                env: decay(0.15))
        }
        for m in [72.0, 76, 79, 84] {
            let f = midi(m + (rising ? 12 : 0))
            add(&o, at: 0.6, duration: 1.0, wave: .saw, amp: 0.08, freq: { _ in f },
                env: adsr(attack: 0.01, decay: 0.1, sustain: 0.7, length: 0.7, release: 0.3))
        }
        return finish(o)
    }

    /// 実績解除(キラリン)
    static func achievement() -> [Float] {
        var o = silence(0.9)
        for (i, m) in [84.0, 88, 91, 96, 100].enumerated() {
            let f = midi(m)
            add(&o, at: Double(i) * 0.05, duration: 0.6, wave: .sine, amp: 0.22, freq: { _ in f }, env: decay(0.25))
            add(&o, at: Double(i) * 0.05, duration: 0.3, wave: .triangle, amp: 0.1, freq: { _ in f * 2 },
                env: decay(0.1))
        }
        return finish(o)
    }

    // MARK: - BGM

    /// ボーナス中・RUSH 中にループする 8 小節(150BPM)。transpose は半音単位。
    /// style: ハイテンポ = 188BPM、8bit = 主旋律も矩形波でビブラートなし、マイナー = Am, F, C, G 進行
    static func bgm(transpose: Double, intense: Bool, style: BGMStyle = .standard) -> [Float] {
        let eighth = style == .highTempo ? 0.16 : 0.2
        let barLength = eighth * 8
        let noteLength = eighth * 0.95
        var o = silence(barLength * 8)
        // C, Am, F, G を 2 回(マイナーは Am, F, C, G)
        let roots: [Double] = style == .minor ? [45, 41, 48, 43, 45, 41, 48, 43] : [48, 45, 41, 43, 48, 45, 41, 43]
        let minor = style == .minor
            ? [true, false, false, false, true, false, false, false]
            : [false, true, false, false, false, true, false, false]
        let leadWave: Wave = style == .eightBit ? .square : .saw
        let vibrato = style == .eightBit ? 0.0 : 0.006
        let melody: [[Double]] = [
            [72, 76, 79, 84, 83, 79, 76, 79],
            [81, -1, 79, 76, 72, 76, 81, 84],
            [84, -1, 81, 77, 81, 84, 86, 84],
            [83, 79, 74, 79, 83, 86, 83, 79],
            [84, 88, 91, 88, 84, 79, 76, 79],
            [81, 84, 88, 84, 81, 76, 72, 76],
            [77, 81, 84, 89, 88, 84, 81, 84],
            [86, 83, 79, 74, 79, 83, 86, 91],
        ]
        for bar in 0..<8 {
            let barStart = Double(bar) * barLength
            let root = roots[bar] + transpose
            let chord: [Double] = [0, minor[bar] ? 3 : 4, 7]

            // ベース: 8 分でルートとオクターブを交互に
            for i in 0..<8 {
                let f = midi(root + (i % 2 == 0 ? 0 : 12))
                add(&o, at: barStart + Double(i) * eighth, duration: noteLength, wave: .square, amp: 0.13, wrap: true,
                    freq: { _ in f }, env: decay(0.1, attack: 0.004))
            }
            // アルペジオ: 16 分で和音を上下
            let arpOrder = [0, 1, 2, 3, 4, 3, 2, 1]
            for i in 0..<16 {
                let k = arpOrder[i % 8]
                let note = root + 24 + chord[k % 3] + Double(k / 3) * 12
                let f = midi(note)
                add(&o, at: barStart + Double(i) * eighth / 2, duration: eighth / 2, wave: .square,
                    amp: intense ? 0.06 : 0.045, wrap: true, freq: { _ in f }, env: decay(0.04, attack: 0.002))
            }
            // 主旋律
            for (i, m) in melody[bar].enumerated() where m > 0 {
                let f = midi(m + transpose)
                add(&o, at: barStart + Double(i) * eighth, duration: noteLength, wave: leadWave,
                    amp: style == .eightBit ? 0.07 : 0.1, wrap: true,
                    freq: { t in f * (1 + vibrato * sin(t * 2 * .pi * 6)) },
                    env: adsr(attack: 0.005, decay: 0.05, sustain: 0.7, length: noteLength - 0.04, release: 0.04))
                add(&o, at: barStart + Double(i) * eighth, duration: noteLength, wave: .square, amp: 0.05, wrap: true,
                    freq: { _ in f * 2 }, env: decay(0.06))
            }
            // ドラム: キック(4 つ打ち) / スネア(2・4 拍) / ハイハット(裏)
            for beat in 0..<4 {
                let t0 = barStart + Double(beat) * eighth * 2
                add(&o, at: t0, duration: 0.18, wave: .sine, amp: 0.75, wrap: true,
                    freq: { t in 45 + 90 * exp(-t / 0.03) }, env: decay(0.08, attack: 0.001))
                if beat % 2 == 1 {
                    add(&o, at: t0, duration: 0.15, wave: .noise, amp: 0.28, wrap: true,
                        freq: { _ in 0 }, env: decay(0.05, attack: 0))
                    add(&o, at: t0, duration: 0.1, wave: .sine, amp: 0.3, wrap: true,
                        freq: { _ in 190 }, env: decay(0.03))
                }
                add(&o, at: t0 + eighth, duration: 0.04, wave: .noise, amp: intense ? 0.13 : 0.09, wrap: true,
                    freq: { _ in 0 }, env: decay(0.012, attack: 0))
                if intense {
                    add(&o, at: t0 + eighth * 0.5, duration: 0.03, wave: .noise, amp: 0.05, wrap: true,
                        freq: { _ in 0 }, env: decay(0.008, attack: 0))
                    add(&o, at: t0 + eighth * 1.5, duration: 0.03, wave: .noise, amp: 0.05, wrap: true,
                        freq: { _ in 0 }, env: decay(0.008, attack: 0))
                }
            }
        }
        return finish(o, gain: 0.9)
    }
}
