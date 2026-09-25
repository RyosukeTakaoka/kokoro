import AVFoundation

/// 合成した効果音と BGM を鳴らす。呼び出しはすべてメインスレッドから。
final class SoundEngine {
    static let shared = SoundEngine()

    enum Effect: Hashable {
        case lever
        case stop
        case reach
        case step(Int)
        /// タメのうなり。長さは 0.1 秒単位
        case riser(tenths: Int)
        case kyuin
        case boom
        case fanfare
        case lose
        case coin
        case smallWin
        case push
        case heartbeat
        case tick(Int)
        case yokoku(Int)
        case cut
        case bonusEnd
        case rushStart
    }

    enum Music: Hashable {
        case bonus
        case rush
    }

    var isEnabled = true {
        didSet {
            if !isEnabled {
                silence()
                stopMusic()
            }
        }
    }

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.rate, channels: 1)!
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private let musicNode = AVAudioPlayerNode()
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private var musicBuffers: [Music: AVAudioPCMBuffer] = [:]
    private var currentMusic: Music?
    private let musicVolume: Float = 0.5

    private init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        for _ in 0..<10 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            voices.append(node)
        }
        engine.attach(musicNode)
        engine.connect(musicNode, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
        engine.prepare()
        try? engine.start()

        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                               queue: .main) { [weak self] _ in
            self?.restart()
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            self?.restart()
        }
    }

    /// よく使う音を裏で先に作っておく(最初の 1 回で引っかからないように)。
    func prewarm() {
        let effects: [Effect] = [.lever, .stop, .reach, .kyuin, .boom, .fanfare, .lose, .coin, .smallWin, .push,
                                 .heartbeat, .cut, .bonusEnd, .rushStart,
                                 .step(0), .step(1), .step(2), .step(3), .step(4), .step(5),
                                 .yokoku(1), .yokoku(2), .yokoku(3), .yokoku(4),
                                 .riser(tenths: 16), .riser(tenths: 18), .riser(tenths: 23), .riser(tenths: 30)]
        DispatchQueue.global(qos: .userInitiated).async {
            var rendered: [(Effect, [Float])] = []
            for e in effects { rendered.append((e, Self.render(e))) }
            let bonus = SoundSynth.bgm(transpose: 0, intense: false)
            let rush = SoundSynth.bgm(transpose: 2, intense: true)
            DispatchQueue.main.async {
                for (e, samples) in rendered where self.buffers[e] == nil {
                    self.buffers[e] = self.makeBuffer(samples)
                }
                if self.musicBuffers[.bonus] == nil { self.musicBuffers[.bonus] = self.makeBuffer(bonus) }
                if self.musicBuffers[.rush] == nil { self.musicBuffers[.rush] = self.makeBuffer(rush) }
            }
        }
    }

    // MARK: 再生

    func play(_ effect: Effect, volume: Float = 1) {
        guard isEnabled else { return }
        ensureRunning()
        let buffer = buffer(for: effect)
        let node = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        node.stop()
        node.volume = volume
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        node.play()
    }

    /// 鳴っている効果音を全部止め、BGM も一瞬消す(タメ直前の「静寂」)。
    func silence() {
        for v in voices { v.stop() }
        musicNode.volume = 0
    }

    /// 静寂から BGM を戻す
    func restoreMusic() {
        musicNode.volume = musicVolume
    }

    func playMusic(_ music: Music) {
        guard isEnabled else { return }
        ensureRunning()
        if currentMusic == music && musicNode.isPlaying {
            musicNode.volume = musicVolume
            return
        }
        let buffer: AVAudioPCMBuffer
        if let cached = musicBuffers[music] {
            buffer = cached
        } else {
            let samples = music == .bonus
                ? SoundSynth.bgm(transpose: 0, intense: false)
                : SoundSynth.bgm(transpose: 2, intense: true)
            buffer = makeBuffer(samples)
            musicBuffers[music] = buffer
        }
        musicNode.stop()
        musicNode.volume = musicVolume
        musicNode.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        musicNode.play()
        currentMusic = music
    }

    func stopMusic() {
        musicNode.stop()
        currentMusic = nil
    }

    // MARK: 内部

    private func buffer(for effect: Effect) -> AVAudioPCMBuffer {
        if let b = buffers[effect] { return b }
        let b = makeBuffer(Self.render(effect))
        buffers[effect] = b
        return b
    }

    private static func render(_ effect: Effect) -> [Float] {
        switch effect {
        case .lever: return SoundSynth.lever()
        case .stop: return SoundSynth.stop()
        case .reach: return SoundSynth.reach()
        case .step(let level): return SoundSynth.step(level)
        case .riser(let tenths): return SoundSynth.riser(Double(tenths) / 10)
        case .kyuin: return SoundSynth.kyuin()
        case .boom: return SoundSynth.boom()
        case .fanfare: return SoundSynth.fanfare()
        case .lose: return SoundSynth.lose()
        case .coin: return SoundSynth.coin()
        case .smallWin: return SoundSynth.smallWin()
        case .push: return SoundSynth.push()
        case .heartbeat: return SoundSynth.heartbeat()
        case .tick(let level): return SoundSynth.tick(level)
        case .yokoku(let level): return SoundSynth.yokoku(level)
        case .cut: return SoundSynth.cut()
        case .bonusEnd: return SoundSynth.jingle(rising: false)
        case .rushStart: return SoundSynth.jingle(rising: true)
        }
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let count = max(1, samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    channel.update(from: base, count: samples.count)
                }
            }
        }
        return buffer
    }

    private func ensureRunning() {
        if !engine.isRunning {
            try? AVAudioSession.sharedInstance().setActive(true)
            try? engine.start()
        }
    }

    private func restart() {
        ensureRunning()
        if let music = currentMusic {
            currentMusic = nil
            playMusic(music)
        }
    }
}
