import Foundation

/// リールに描かれている図柄。
enum SlotSymbol: Int, CaseIterable, Hashable {
    case seven
    case bar
    case bell
    case watermelon
    case cherry
    case replay

    /// ボーナス図柄(7 と BAR)かどうか。リーチになるのはこの 2 つだけ。
    var isBonusSymbol: Bool { self == .seven || self == .bar }
}

/// 3 本のリールの図柄の並び(21 コマ)。
/// 止める位置は抽選で決まった図柄に差し替えるので、ここは「回っているときの見た目」用。
enum ReelStrip {
    static let length = 21

    static let strips: [[SlotSymbol]] = [
        [.seven, .bell, .replay, .cherry, .watermelon, .bar, .bell, .replay, .seven, .watermelon, .bell,
         .replay, .cherry, .bar, .bell, .replay, .watermelon, .seven, .bell, .replay, .bar],
        [.bell, .seven, .replay, .watermelon, .bell, .bar, .cherry, .replay, .bell, .seven, .watermelon,
         .replay, .bell, .bar, .cherry, .replay, .seven, .bell, .watermelon, .replay, .bar],
        [.replay, .bell, .seven, .watermelon, .replay, .bar, .bell, .cherry, .replay, .seven, .bell,
         .watermelon, .replay, .bar, .bell, .seven, .cherry, .replay, .bell, .watermelon, .bar],
    ]

    static func symbol(reel: Int, index: Int) -> SlotSymbol {
        let strip = strips[reel]
        let i = ((index % length) + length) % length
        return strip[i]
    }
}
