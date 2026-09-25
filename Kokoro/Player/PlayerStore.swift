import Foundation
import Observation

/// プレイヤー(自分)のデータ。メダル・実績・演出図鑑・見た目の設定など、どの台に座っても持ち歩くもの。
@MainActor
@Observable
final class PlayerStore {
    struct Saved: Codable {
        var credits = 500
        var borrowed = 0
        var soundOn = true
        var hapticsOn = true
        var achievements: Set<String> = []
        /// 見たことのあるリーチ色(ExpectColor.rawValue)
        var seenColors: Set<Int> = []
        /// 見たことのある違和感の数
        var anomaliesSeen = 0
        var lifetimeSpins = 0
        var lifetimeBonuses = 0
        var freezeCount = 0
        var bestChain = 0
        var bestRushTotal = 0
        var theme: CabinetTheme = .standard
        var bgm: BGMStyle = .standard
    }

    static let startingCredits = 500
    static let refillAmount = 500

    var credits: Int { didSet { save() } }
    var borrowed: Int { didSet { save() } }
    var soundOn: Bool {
        didSet {
            SoundEngine.shared.isEnabled = soundOn
            save()
        }
    }
    var hapticsOn: Bool {
        didSet {
            HapticEngine.shared.isEnabled = hapticsOn
            save()
        }
    }
    private(set) var achievements: Set<String>
    private(set) var seenColors: Set<Int>
    var anomaliesSeen: Int { didSet { save() } }
    var lifetimeSpins: Int { didSet { save() } }
    var lifetimeBonuses: Int { didSet { save() } }
    var freezeCount: Int { didSet { save() } }
    var bestChain: Int { didSet { save() } }
    var bestRushTotal: Int { didSet { save() } }
    var theme: CabinetTheme { didSet { save() } }
    var bgm: BGMStyle {
        didSet {
            SoundEngine.shared.bgmStyle = bgm
            save()
        }
    }

    private static let key = "player"
    @ObservationIgnored private var loading = true

    init() {
        let d = UserDefaults.standard
        var saved = Saved()
        if let data = d.data(forKey: Self.key), let decoded = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = decoded
        } else if d.object(forKey: "credits") != nil {
            // 最初の版(台の概念が無かったころ)のメダルを引き継ぐ
            saved.credits = d.integer(forKey: "credits")
            saved.borrowed = d.integer(forKey: "borrowed")
        }
        credits = saved.credits
        borrowed = saved.borrowed
        soundOn = saved.soundOn
        hapticsOn = saved.hapticsOn
        achievements = saved.achievements
        seenColors = saved.seenColors
        anomaliesSeen = saved.anomaliesSeen
        lifetimeSpins = saved.lifetimeSpins
        lifetimeBonuses = saved.lifetimeBonuses
        freezeCount = saved.freezeCount
        bestChain = saved.bestChain
        bestRushTotal = saved.bestRushTotal
        theme = saved.theme
        bgm = saved.bgm
        SoundEngine.shared.isEnabled = soundOn
        SoundEngine.shared.bgmStyle = bgm
        HapticEngine.shared.isEnabled = hapticsOn
        loading = false
    }

    /// 借りたぶんを引いた差枚
    var netMedals: Int { credits - borrowed - Self.startingCredits }

    func has(_ achievement: Achievement) -> Bool { achievements.contains(achievement.rawValue) }

    /// 実績を解除する。初めて解除したときだけ true
    @discardableResult
    func unlock(_ achievement: Achievement) -> Bool {
        guard !has(achievement) else { return false }
        achievements.insert(achievement.rawValue)
        save()
        return true
    }

    /// リーチ色を図鑑に記録する。初めて見た色なら true
    @discardableResult
    func see(_ color: ExpectColor) -> Bool {
        guard !seenColors.contains(color.rawValue) else { return false }
        seenColors.insert(color.rawValue)
        save()
        return true
    }

    func isUnlocked(_ theme: CabinetTheme) -> Bool {
        guard let needed = theme.unlockedBy else { return true }
        return has(needed)
    }

    func isUnlocked(_ bgm: BGMStyle) -> Bool {
        guard let needed = bgm.unlockedBy else { return true }
        return has(needed)
    }

    func resetMedals() {
        credits = Self.startingCredits
        borrowed = 0
    }

    private func save() {
        guard !loading else { return }
        let saved = Saved(credits: credits, borrowed: borrowed, soundOn: soundOn, hapticsOn: hapticsOn,
                          achievements: achievements, seenColors: seenColors, anomaliesSeen: anomaliesSeen,
                          lifetimeSpins: lifetimeSpins, lifetimeBonuses: lifetimeBonuses,
                          freezeCount: freezeCount, bestChain: bestChain, bestRushTotal: bestRushTotal,
                          theme: theme, bgm: bgm)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
