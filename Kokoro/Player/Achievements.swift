import SwiftUI

/// 実績(トロフィー)。解除すると筐体の色や BGM が増える。
enum Achievement: String, CaseIterable, Identifiable {
    case spins1000
    case spins10000
    case allColors
    case oneGameRenchan
    case freeze
    case chain5
    case chain10
    case superRush
    case ceiling
    case anomalyWin
    case oneShot1000
    case rainbowHint

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spins1000: return "1,000 回転"
        case .spins10000: return "10,000 回転"
        case .allColors: return "リーチ色コンプリート"
        case .oneGameRenchan: return "1G 連"
        case .freeze: return "フリーズ"
        case .chain5: return "5 連チャン"
        case .chain10: return "10 連チャン"
        case .superRush: return "SUPER KOKORO RUSH"
        case .ceiling: return "天井到達"
        case .anomalyWin: return "違和感を見逃さない"
        case .oneShot1000: return "一撃 1,000 枚"
        case .rainbowHint: return "虹の示唆"
        }
    }

    var detail: String {
        switch self {
        case .spins1000: return "累計 1,000 回転"
        case .spins10000: return "累計 10,000 回転"
        case .allColors: return "青・緑・赤・金・虹のリーチを全部見る"
        case .oneGameRenchan: return "ボーナス後 1 回転目で次のボーナスを引く"
        case .freeze: return "1/4000 のロングフリーズを引く"
        case .chain5: return "RUSH で 5 連チャン"
        case .chain10: return "RUSH で 10 連チャン"
        case .superRush: return "上位 RUSH に昇格する"
        case .ceiling: return "600G ハマって天井に届く"
        case .anomalyWin: return "違和感が出た回転でボーナスを引く"
        case .oneShot1000: return "1 回の RUSH で 1,000 枚獲得"
        case .rainbowHint: return "ボーナス終了時に虹の示唆(設定 6 確定)を見る"
        }
    }

    /// 解除でもらえるもの(表示用)
    var rewardText: String? {
        if let t = CabinetTheme.allCases.first(where: { $0.unlockedBy == self }) { return "筐体「\(t.title)」" }
        if let b = BGMStyle.allCases.first(where: { $0.unlockedBy == self }) { return "BGM「\(b.title)」" }
        return nil
    }
}

/// 筐体の色
enum CabinetTheme: String, CaseIterable, Codable, Identifiable {
    case standard
    case neonBlue
    case sakura
    case gold
    case shikkoku
    case rainbow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "スタンダード"
        case .neonBlue: return "ネオンブルー"
        case .sakura: return "サクラ"
        case .gold: return "ゴールド"
        case .shikkoku: return "漆黒"
        case .rainbow: return "レインボー"
        }
    }

    var unlockedBy: Achievement? {
        switch self {
        case .standard: return nil
        case .neonBlue: return .spins1000
        case .sakura: return .oneGameRenchan
        case .gold: return .spins10000
        case .shikkoku: return .freeze
        case .rainbow: return .chain10
        }
    }

    /// 筐体本体のグラデーション
    var bodyColors: [Color] {
        switch self {
        case .standard: return [Color(white: 0.2), Color(white: 0.06), Color(white: 0.14)]
        case .neonBlue: return [Color(red: 0.05, green: 0.2, blue: 0.35), Color(red: 0.01, green: 0.04, blue: 0.1),
                                Color(red: 0.03, green: 0.12, blue: 0.25)]
        case .sakura: return [Color(red: 0.45, green: 0.2, blue: 0.3), Color(red: 0.15, green: 0.05, blue: 0.1),
                              Color(red: 0.35, green: 0.15, blue: 0.25)]
        case .gold: return [Color(red: 0.55, green: 0.42, blue: 0.12), Color(red: 0.18, green: 0.12, blue: 0.02),
                            Color(red: 0.45, green: 0.33, blue: 0.08)]
        case .shikkoku: return [Color(white: 0.08), Color.black, Color(red: 0.2, green: 0, blue: 0.02)]
        case .rainbow: return [Color(red: 0.3, green: 0.1, blue: 0.4), Color(red: 0.05, green: 0.05, blue: 0.2),
                               Color(red: 0.1, green: 0.3, blue: 0.3)]
        }
    }

    /// ロゴの色
    var logo: [Color] {
        switch self {
        case .standard: return [Color(red: 1, green: 0.5, blue: 0.75), Color(red: 0.7, green: 0.35, blue: 1)]
        case .neonBlue: return [Color(red: 0.3, green: 0.9, blue: 1), Color(red: 0.3, green: 0.4, blue: 1)]
        case .sakura: return [Color(red: 1, green: 0.8, blue: 0.9), Color(red: 1, green: 0.45, blue: 0.65)]
        case .gold: return [Color(red: 1, green: 0.95, blue: 0.6), Color(red: 0.95, green: 0.65, blue: 0.1)]
        case .shikkoku: return [Color(red: 1, green: 0.2, blue: 0.2), Color(red: 0.6, green: 0, blue: 0)]
        case .rainbow: return [.red, .orange, .yellow, .green, .cyan, .purple]
        }
    }

    /// ふちを走るランプの色(通常時)
    var chase: Color {
        switch self {
        case .standard: return Color(red: 0.8, green: 0.5, blue: 1)
        case .neonBlue: return Color(red: 0.3, green: 0.9, blue: 1)
        case .sakura: return Color(red: 1, green: 0.6, blue: 0.8)
        case .gold: return Color(red: 1, green: 0.85, blue: 0.3)
        case .shikkoku: return Color(red: 1, green: 0.15, blue: 0.15)
        case .rainbow: return .white
        }
    }
}

/// ボーナス中・RUSH 中の BGM の曲調
enum BGMStyle: String, CaseIterable, Codable, Identifiable {
    case standard
    case highTempo
    case eightBit
    case minor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "スタンダード"
        case .highTempo: return "ハイテンポ"
        case .eightBit: return "8bit"
        case .minor: return "マイナー"
        }
    }

    var unlockedBy: Achievement? {
        switch self {
        case .standard: return nil
        case .highTempo: return .chain5
        case .eightBit: return .allColors
        case .minor: return .ceiling
        }
    }
}
