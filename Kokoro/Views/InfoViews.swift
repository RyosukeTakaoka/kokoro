import SwiftUI

/// 台データ(設定推測の材料)とスペック表・答え合わせ
struct MachineInfoView: View {
    let game: SlotGame
    @Environment(\.dismiss) var dismiss
    @State var confirmReveal = false

    var body: some View {
        let data = game.machineData
        NavigationStack {
            List {
                Section {
                    row("総回転数", "\(data.totalGames)G")
                    row("現在のハマり", "\(data.gamesSinceBonus)G  (天井 \(SlotLottery.ceiling)G)")
                    row("BIG", "\(data.bigCount) 回  \(rate(data.totalGames, data.bigCount))")
                    row("REG", "\(data.regCount) 回  \(rate(data.totalGames, data.regCount))")
                    row("ベル", "\(data.bellCount) 回  \(rate(data.totalGames, data.bellCount))")
                    row("最大連チャン", "\(data.maxChain) 連")
                } header: {
                    Text("\(game.machineNumber)番台 の今日のデータ")
                } footer: {
                    Text("BIG・REG・ベルは設定が高いほど軽くなります。下のスペック表と見比べて推測してください。")
                }

                Section {
                    if data.hints.isEmpty {
                        Text("まだボーナスが終わっていません").foregroundStyle(.secondary)
                    } else {
                        Text(data.hints.map(\.emoji).joined(separator: " "))
                            .font(.title3)
                        ForEach(SettingHint.allCases, id: \.self) { hint in
                            let count = data.hints.filter { $0 == hint }.count
                            if count > 0 {
                                row("\(hint.emoji) \(hint.meaning)", "\(count) 回")
                            }
                        }
                    }
                } header: {
                    Text("ボーナス終了時の示唆")
                } footer: {
                    Text("🔵 奇数寄り / 🔴 偶数寄り / 🟡 設定4以上 / 🌈 設定6")
                }

                if !data.history.isEmpty {
                    Section {
                        ForEach(data.history) { record in
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
                        Text("ボーナス履歴(新しい順)")
                    }
                }

                Section {
                    ForEach(MachineSetting.all, id: \.level) { s in
                        HStack {
                            Text("設定\(s.level)").fontWeight(.bold)
                            Spacer()
                            Text("B 1/\(Int((1 / s.big).rounded()))  R 1/\(Int((1 / s.reg).rounded()))  ベル 1/\(String(format: "%.1f", 1 / s.bell))")
                                .font(.system(.caption, design: .monospaced))
                            Text(String(format: "%.1f%%", s.payoutRate))
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(s.payoutRate >= 100 ? Color.green : Color.secondary)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                    row("RUSH(15G)", "継続 約66%")
                    row("SUPER RUSH(15G)", "継続 約80%")
                    row("SUPER への昇格", "\(SlotLottery.superChain)連目 か RUSH中スイカ1/3")
                    row("駆け抜け救済", "\(SlotLottery.zoneGames)G ボーナス確率2倍")
                    row("ロングフリーズ", "1/4000 (BIG+SUPER)")
                    row("リーチ信頼度", "青3% 緑9% 赤44% 金78% 虹100%")
                    row("違和感", "出たらボーナス期待度 約35%")
                } header: {
                    Text("スペック")
                }

                Section {
                    if data.revealed {
                        row("この台の今日の設定", "設定\(game.setting.level)")
                    } else {
                        Button("答え合わせ(設定を見る)") { confirmReveal = true }
                    }
                } footer: {
                    Text("見ると今日はずっとホールにも表示されます(推測の楽しみが無くなります)。")
                }

                Section {
                    Toggle("効果音・BGM", isOn: Binding(get: { game.player.soundOn },
                                                    set: { game.player.soundOn = $0 }))
                    Toggle("振動", isOn: Binding(get: { game.player.hapticsOn },
                                               set: { game.player.hapticsOn = $0 }))
                } header: {
                    Text("演出")
                }
            }
            .navigationTitle("台データ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .confirmationDialog("今日のこの台の設定を見ますか?", isPresented: $confirmReveal, titleVisibility: .visible) {
                Button("見る") { game.revealSetting() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func rate(_ games: Int, _ count: Int) -> String {
        count > 0 ? "(1/\(String(format: "%.1f", Double(games) / Double(count))))" : ""
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// 実績・演出図鑑・カスタマイズ
struct AchievementsView: View {
    @Bindable var player: PlayerStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        ForEach(ExpectColor.allCases, id: \.self) { color in
                            let seen = player.seenColors.contains(color.rawValue)
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(seen ? AnyShapeStyle(color == .rainbow ? AnyShapeStyle(RainbowFill.angular(phase: 0))
                                                                                  : AnyShapeStyle(color.color))
                                               : AnyShapeStyle(Color.gray.opacity(0.25)))
                                    .frame(width: 34, height: 34)
                                    .overlay(Text(seen ? "" : "?").foregroundStyle(.secondary))
                                Text(seen ? color.name : "???")
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    LabeledContent("見つけた違和感", value: "\(player.anomaliesSeen) 回")
                    LabeledContent("フリーズ", value: "\(player.freezeCount) 回")
                    LabeledContent("最大連チャン", value: "\(player.bestChain) 連")
                    LabeledContent("RUSH 最高獲得", value: "\(player.bestRushTotal) 枚")
                    LabeledContent("累計ボーナス", value: "\(player.lifetimeBonuses) 回")
                    LabeledContent("累計回転", value: "\(player.lifetimeSpins) G")
                } header: {
                    Text("演出図鑑・記録")
                }

                Section {
                    ForEach(Achievement.allCases) { a in
                        let done = player.has(a)
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: done ? "trophy.fill" : "lock.fill")
                                .foregroundStyle(done ? Color.yellow : Color.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.title).fontWeight(.bold)
                                Text(a.detail).font(.caption).foregroundStyle(.secondary)
                                if let reward = a.rewardText {
                                    Text("ごほうび: \(reward)").font(.caption).foregroundStyle(done ? Color.yellow : Color.secondary)
                                }
                            }
                        }
                        .opacity(done ? 1 : 0.7)
                    }
                } header: {
                    Text("実績 \(player.achievements.count)/\(Achievement.allCases.count)")
                }

                Section {
                    ForEach(CabinetTheme.allCases) { theme in
                        let unlocked = player.isUnlocked(theme)
                        Button {
                            player.theme = theme
                        } label: {
                            HStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(LinearGradient(colors: theme.bodyColors, startPoint: .top, endPoint: .bottom))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.chase, lineWidth: 2))
                                    .frame(width: 44, height: 28)
                                Text(unlocked ? theme.title : "???")
                                Spacer()
                                if player.theme == theme {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                } else if !unlocked {
                                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(!unlocked)
                    }
                } header: {
                    Text("筐体の色")
                }

                Section {
                    ForEach(BGMStyle.allCases) { style in
                        let unlocked = player.isUnlocked(style)
                        Button {
                            player.bgm = style
                        } label: {
                            HStack {
                                Text(unlocked ? style.title : "???")
                                Spacer()
                                if player.bgm == style {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                } else if !unlocked {
                                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(!unlocked)
                    }
                } header: {
                    Text("ボーナス・RUSH の BGM")
                }
            }
            .navigationTitle("実績と図鑑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
