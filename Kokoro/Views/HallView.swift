import SwiftUI

/// ホール: 並んでいる台からデータを見て 1 台選ぶ。
/// 台の上のデータランプ(今日の回転数・BIG/REG・履歴)を見て「この台、設定 6 かも?」と推測するのが楽しみ方。
struct HallView: View {
    let player: PlayerStore
    let hall: HallStore
    let onSit: (Int) -> Void
    @State private var showAchievements = false
    @State private var showSettings = false

    init(player: PlayerStore, hall: HallStore, onSit: @escaping (Int) -> Void) {
        self.player = player
        self.hall = hall
        self.onSit = onSit
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.02, blue: 0.15), Color(red: 0.02, green: 0.01, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Hall.machineNumbers, id: \.self) { number in
                            MachineCard(number: number, data: hall.data(for: number),
                                        setting: hall.setting(for: number), theme: player.theme) {
                                onSit(number)
                            }
                        }
                    }
                    Text("設定(1〜6)は毎日 0:00(日本時間)に入れ替わります。\n台のデータ・ボーナス終了時の示唆・ベル確率から推測してみてください。")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(16)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { hall.rollOverIfNeeded() }
        .sheet(isPresented: $showAchievements) {
            AchievementsView(player: player)
        }
        .sheet(isPresented: $showSettings) {
            PlayerSettingsView(player: player)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("KOKORO HALL")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .italic()
                        .foregroundStyle(LinearGradient(colors: player.theme.logo, startPoint: .leading,
                                                        endPoint: .trailing))
                    Text("\(hall.day) 営業")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Button { showAchievements = true } label: {
                    Image(systemName: "trophy.fill").frame(width: 40, height: 40)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .accessibilityLabel("実績と演出図鑑")
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill").frame(width: 40, height: 40)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .accessibilityLabel("設定")
            }
            .foregroundStyle(.white)
            HStack(spacing: 10) {
                LEDCounter(label: "CREDIT", value: player.credits, color: .orange)
                LEDCounter(label: "差枚", value: player.netMedals, color: player.netMedals >= 0 ? .green : .red,
                           signed: true)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("実績 \(player.achievements.count)/\(Achievement.allCases.count)")
                    Text("累計 \(player.lifetimeSpins)G")
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

/// 台 1 台ぶんのカード(データランプ付き)
private struct MachineCard: View {
    let number: Int
    let data: MachineData
    let setting: MachineSetting
    let theme: CabinetTheme
    let action: () -> Void

    /// 将来の多人数用: 他の人が座っていたら選べない
    private var takenByOthers: Bool {
        if let occupant = data.occupant { return occupant != "me" }
        return false
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack {
                    Text("\(number)")
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                    Spacer()
                    if data.revealed {
                        Text("設定\(setting.level)")
                            .font(.system(size: 12, weight: .heavy))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(setting.level >= 5 ? Color.red : Color.gray))
                            .foregroundStyle(.white)
                    } else if takenByOthers {
                        Text("使用中")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.orange)
                    }
                }
                // データランプ
                VStack(spacing: 4) {
                    dataRow("回転", "\(data.gamesSinceBonus)", color: .white)
                    dataRow("BIG", "\(data.bigCount)", color: Color(red: 1, green: 0.35, blue: 0.35))
                    dataRow("REG", "\(data.regCount)", color: Color(red: 0.45, green: 0.7, blue: 1))
                    dataRow("総回転", "\(data.totalGames)", color: .white.opacity(0.7))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.7)))
                // 最近のボーナス(左が新しい)
                HStack(spacing: 4) {
                    ForEach(data.history.prefix(8)) { record in
                        Circle()
                            .fill(record.kind == .big ? Color.red : Color.blue)
                            .frame(width: 8, height: 8)
                    }
                    Spacer(minLength: 0)
                    if data.maxChain >= 2 {
                        Text("最大\(data.maxChain)連")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.yellow)
                    }
                }
                .frame(height: 12)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: theme.bodyColors, startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.chase.opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(PressDownStyle())
        .disabled(takenByOthers)
        .accessibilityLabel("\(number)番台 回転数\(data.gamesSinceBonus) BIG\(data.bigCount) REG\(data.regCount)")
    }

    private func dataRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

/// プレイヤー全体の設定(音・振動・メダルのリセット)
struct PlayerSettingsView: View {
    @Bindable var player: PlayerStore
    @Environment(\.dismiss) var dismiss
    @State var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("効果音・BGM", isOn: $player.soundOn)
                    Toggle("振動", isOn: $player.hapticsOn)
                    if !HapticEngine.shared.supportsHaptics {
                        Text("この端末は振動(Taptic Engine)に対応していません。iPhone で遊ぶと振動します。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("演出")
                }
                Section {
                    LabeledContent("クレジット", value: "\(player.credits) 枚")
                    LabeledContent("借りたメダル", value: "\(player.borrowed) 枚")
                    LabeledContent("差枚", value: String(format: "%+ld 枚", player.netMedals))
                    Button("メダルを最初に戻す", role: .destructive) { confirmReset = true }
                } header: {
                    Text("メダル")
                } footer: {
                    Text("このアプリのメダルはただの数字です。お金とは交換できません。実績と図鑑は消えません。")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .confirmationDialog("メダルを 500 枚に戻しますか?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("戻す", role: .destructive) { player.resetMedals() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
