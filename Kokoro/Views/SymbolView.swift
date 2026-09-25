import SwiftUI

/// リールの図柄 1 つ。画像素材を使わず、文字と図形で描く。
struct SymbolView: View {
    let symbol: SlotSymbol
    let size: CGFloat

    var body: some View {
        switch symbol {
        case .seven:
            SevenMark(size: size)
        case .bar:
            BarMark(size: size)
        case .bell:
            emoji("🔔")
        case .watermelon:
            emoji("🍉")
        case .cherry:
            emoji("🍒")
        case .replay:
            Text("REPLAY")
                .font(.system(size: size * 0.2, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, size * 0.08)
                .frame(width: size * 0.9, height: size * 0.36)
                .background(
                    Capsule().fill(LinearGradient(colors: [Color(red: 0.3, green: 0.6, blue: 1),
                                                           Color(red: 0.05, green: 0.25, blue: 0.8)],
                                                  startPoint: .top, endPoint: .bottom))
                )
                .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 2))
        }
    }

    private func emoji(_ s: String) -> some View {
        Text(s)
            .font(.system(size: size * 0.62))
            .shadow(color: .black.opacity(0.35), radius: 1, x: 1, y: 2)
    }
}

/// 赤い 7
private struct SevenMark: View {
    let size: CGFloat

    var body: some View {
        let font = Font.system(size: size * 0.86, weight: .black, design: .rounded).italic()
        ZStack {
            // 影と縁取り
            Text("7").font(font).foregroundStyle(Color(red: 0.25, green: 0, blue: 0)).offset(x: 3, y: 3)
            Text("7").font(font).foregroundStyle(.white).offset(x: -1.5, y: -1.5)
            Text("7").font(font)
                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.55, blue: 0.45),
                                                         Color(red: 0.95, green: 0.05, blue: 0.1),
                                                         Color(red: 0.55, green: 0, blue: 0.02)],
                                                startPoint: .top, endPoint: .bottom))
        }
    }
}

/// 黒地に金の BAR
private struct BarMark: View {
    let size: CGFloat

    var body: some View {
        Text("BAR")
            .font(.system(size: size * 0.26, weight: .black, design: .serif))
            .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.6),
                                                     Color(red: 0.95, green: 0.7, blue: 0.1)],
                                            startPoint: .top, endPoint: .bottom))
            .frame(width: size * 0.82, height: size * 0.42)
            .background(RoundedRectangle(cornerRadius: size * 0.06).fill(Color(white: 0.08)))
            .overlay(RoundedRectangle(cornerRadius: size * 0.06)
                .stroke(Color(red: 1, green: 0.8, blue: 0.2), lineWidth: 3))
    }
}
