import SwiftUI

/// 設定とデータカウンター
struct SettingsView: View {
    @Bindable var game: SlotGame
    @Environment(\.dismiss) var dismiss
    @State var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("効果音・BGM", isOn: $game.soundOn)
                    Toggle("振動", isOn: $game.hapticsOn)
                    if !HapticEngine.shared.supportsHaptics {
                        Text("この端末は振動(Taptic Engine)に対応していません。iPhone で遊ぶと振動します。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("演出")
                }

                Section {
                    row("総回転数", "\(game.totalGames)G")
                    row("ボーナス間のハマり", "\(game.gamesSinceBonus)G")
                    row("BIG", "\(game.bigCount) 回")
                    row("REG", "\(game.regCount) 回")
                    row("差枚", String(format: "%+ld 枚", game.netMedals))
                    row("借りたメダル", "\(game.borrowed) 枚")
                } header: {
                    Text("データ")
                }

                if !game.history.isEmpty {
                    Section {
                        ForEach(game.history) { record in
                            HStack {
                                Text(record.kind == .big ? "BIG" : "REG")
                                    .font(.system(.body, design: .monospaced).weight(.heavy))
                                    .foregroundStyle(record.kind == .big ? Color.red : Color.blue)
                                Spacer()
                                Text("\(record.games)G")
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    } header: {
                        Text("ボーナス履歴(新しい順・この起動のあいだだけ)")
                    }
                }

                Section {
                    row("BIG (16G)", "1/80")
                    row("REG (6G)", "1/110")
                    row("RUSH (15G)", "1/14.5 ・継続 約66%")
                    row("リーチ 青 / 緑", "3% / 9%")
                    row("リーチ 赤 / 金", "44% / 78%")
                    row("リーチ 虹", "確定")
                    row("機械割", "約101%")
                } header: {
                    Text("スペック(テスト用なので甘め)")
                } footer: {
                    Text("このアプリのメダルはただの数字です。お金とは交換できません。")
                }

                Section {
                    Button("データをリセット", role: .destructive) { confirmReset = true }
                        .disabled(game.phase != .idle)
                }
            }
            .navigationTitle("Kokoro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .confirmationDialog("メダルとデータを最初に戻しますか?", isPresented: $confirmReset,
                                titleVisibility: .visible) {
                Button("リセットする", role: .destructive) { game.resetData() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
