import Foundation
import Observation

/// ホール(台が並んでいるお店)。
///
/// 台ごとのデータ(その日の回転数・ボーナス回数・履歴など)は台に紐づけて持ち、
/// メダルや実績はプレイヤー(`PlayerStore`)が持つ。いまは 1 人用だが、将来は
/// 多人数で同じホールに入り「その台に誰が座っているか」を共有する想定で分けてある
/// (`MachineData.occupant` がその席の持ち主を入れる場所)。
enum Hall {
    /// 並んでいる台の番号
    static let machineNumbers = Array(101...108)

    /// 営業日(日本時間の 0:00 で切り替わる)。例: "2026-09-25"
    static func businessDay(_ date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// その日のその台の設定(1〜6)。日付と台番号から決まるので、同じ日なら何度開いても同じ。
    /// 配分は 設定1: 30% / 2: 20% / 3: 20% / 4: 15% / 5: 10% / 6: 5%
    static func setting(machine: Int, day: String) -> Int {
        let x = unitHash("\(day)#\(machine)#kokoro")
        let table: [(Int, Double)] = [(1, 0.30), (2, 0.20), (3, 0.20), (4, 0.15), (5, 0.10), (6, 0.05)]
        var acc = 0.0
        for (level, weight) in table {
            acc += weight
            if x < acc { return level }
        }
        return 6
    }

    /// 文字列から 0〜1 の数を作る(FNV-1a)。乱数の種を毎回同じにするため
    private static func unitHash(_ s: String) -> Double {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100_0000_01b3
        }
        // 下位ビットが偏らないように混ぜる
        h ^= h >> 33
        h = h &* 0xff51_afd7_ed55_8ccd
        h ^= h >> 33
        return Double(h % 1_000_000) / 1_000_000
    }
}

/// 台 1 台ぶんの、その営業日のデータ(データカウンターに出る数字)
struct MachineData: Codable, Equatable {
    struct Record: Codable, Equatable, Identifiable {
        var id: Int
        var kind: BonusKind
        /// 当たるまでにかかった回転数
        var games: Int
    }

    var day: String
    var gamesSinceBonus = 0
    var totalGames = 0
    var bigCount = 0
    var regCount = 0
    var bellCount = 0
    /// 新しい順
    var history: [Record] = []
    /// ボーナス終了時に出た設定示唆
    var hints: [SettingHint] = []
    /// 今日いちばん大きかった連チャン
    var maxChain = 0
    /// 答え合わせ(設定を見た)をしたか
    var revealed = false
    /// 座っている人。いまは自分だけなので "me" か nil。多人数にしたらプレイヤー ID を入れる
    var occupant: String?

    init(day: String) {
        self.day = day
    }

    var bonusCount: Int { bigCount + regCount }

    /// ベル確率(1/x の x)。回していなければ nil
    var bellRate: Double? {
        bellCount > 0 ? Double(totalGames) / Double(bellCount) : nil
    }
}

/// ホールにある台のデータをまとめて持ち、端末に保存する
@MainActor
@Observable
final class HallStore {
    private(set) var machines: [Int: MachineData] = [:]
    private(set) var day: String

    private static let key = "hall.machines"

    init() {
        day = Hall.businessDay()
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Int: MachineData].self, from: data) {
            machines = saved
        }
        rollOverIfNeeded()
    }

    /// 日付が変わっていたら、全台のデータを新しい営業日で作り直す(設定も変わる)
    func rollOverIfNeeded() {
        let today = Hall.businessDay()
        day = today
        for number in Hall.machineNumbers where machines[number]?.day != today {
            machines[number] = MachineData(day: today)
        }
        save()
    }

    func data(for number: Int) -> MachineData {
        machines[number] ?? MachineData(day: day)
    }

    func setting(for number: Int) -> MachineSetting {
        MachineSetting.level(Hall.setting(machine: number, day: day))
    }

    func update(_ number: Int, _ change: (inout MachineData) -> Void) {
        var d = data(for: number)
        change(&d)
        machines[number] = d
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(machines) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
