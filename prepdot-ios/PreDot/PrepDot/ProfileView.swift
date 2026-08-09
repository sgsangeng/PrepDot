import SwiftUI
import Charts

/// Tab 页版（无 dismiss）
struct ProfileTabView: View {
    var body: some View {
        NavigationStack {
            ProfileView()
        }
    }
}

struct ProfileView: View {
    @Environment(AuthManager.self) var auth
    @State private var stats: UserStats? = nil
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if loading {
                    ProgressView("加载中…").padding(.top, 60)
                } else if let s = stats {
                    avatarSection
                    streakSection(s)
                    overviewGrid(s)
                    weeklyChart(s)
                    memorySection(s)
                    settingsSection
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await loadStats() }
        .task { await loadStats() }
    }

    // MARK: - 头像区

    private var avatarSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [Color(hex: auth.avatarColor) ?? .indigo,
                                                Color(hex: auth.avatarColor)?.opacity(0.7) ?? .purple],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: (Color(hex: auth.avatarColor) ?? .indigo).opacity(0.4), radius: 12, y: 4)
                Text(String(auth.nickname.prefix(1)).uppercased())
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(auth.nickname).font(.title2.bold())
            Text("@\(UserDefaults.standard.string(forKey: "username") ?? "")")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(.top, 20)
    }

    // MARK: - 连续打卡

    private func streakSection(_ s: UserStats) -> some View {
        HStack(spacing: 12) {
            // 进度环
            ZStack {
                Circle()
                    .stroke(Color.indigo.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: min(1, Double(s.todayReviewed) / Double(max(1, auth.studyTarget))))
                    .stroke(LinearGradient(colors: [.indigo, .purple],
                                          startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(min(100, Double(s.todayReviewed) / Double(max(1, auth.studyTarget)) * 100)))%")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundColor(.indigo)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("🔥").font(.headline)
                    Text("\(s.streakDays) 天连续打卡").font(.headline)
                }
                Text("今日已复习 \(s.todayReviewed) 张 · 目标 \(auth.studyTarget) 张")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Color.indigo.opacity(0.08), Color.purple.opacity(0.05)],
                           startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.indigo.opacity(0.12), lineWidth: 1))
        .padding(.horizontal)
    }

    // MARK: - 概览四格

    private func overviewGrid(_ s: UserStats) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            MiniStatCard(value: "\(s.totalDecks)",    label: "卡组",   icon: "folder.fill",          color: .indigo)
            MiniStatCard(value: "\(s.totalCards)",    label: "卡片",   icon: "rectangle.stack.fill",  color: .purple)
            MiniStatCard(value: "\(s.totalReviewed)", label: "总复习", icon: "checkmark.circle.fill",  color: Color(red: 0.5, green: 0.3, blue: 0.9))
            MiniStatCard(value: "\(s.avgMemoryScore)%", label: "记忆度", icon: "brain",               color: Color(red: 0.85, green: 0.3, blue: 0.75))
        }
        .padding(.horizontal)
    }

    // MARK: - 近7天折线图

    private func weeklyChart(_ s: UserStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("近 7 天复习").font(.headline).padding(.horizontal)

            Chart {
                ForEach(last7Days(s.weeklyData)) { item in
                    BarMark(x: .value("日期", item.label), y: .value("数量", item.count))
                        .foregroundStyle(
                            LinearGradient(colors: [.indigo, .purple],
                                           startPoint: .bottom, endPoint: .top)
                        )
                        .cornerRadius(5)
                }
            }
            .frame(height: 140)
            .padding(.horizontal)
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(.caption2) }
            }
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().font(.caption2) }
            }
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 记忆度分布（indigo/pink 配色）

    private func memorySection(_ s: UserStats) -> some View {
        let d = s.memoryDistribution
        let total = max(1, d.low + d.mid + d.high)

        return VStack(alignment: .leading, spacing: 14) {
            Text("记忆度分布").font(.headline)

            // 分布条
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if d.low  > 0 { roundedRect(width: geo.size.width * CGFloat(d.low)  / CGFloat(total), color: Color(red: 0.95, green: 0.75, blue: 0.85)) }
                    if d.mid  > 0 { roundedRect(width: geo.size.width * CGFloat(d.mid)  / CGFloat(total), color: Color(red: 0.7, green: 0.5, blue: 0.9)) }
                    if d.high > 0 { roundedRect(width: geo.size.width * CGFloat(d.high) / CGFloat(total), color: Color.indigo) }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)

            // 图例
            HStack(spacing: 20) {
                LegendItem(color: Color(red: 0.95, green: 0.75, blue: 0.85), label: "待加强", count: d.low)
                LegendItem(color: Color(red: 0.7, green: 0.5, blue: 0.9),   label: "进行中", count: d.mid)
                LegendItem(color: .indigo,                                   label: "已掌握", count: d.high)
                Spacer()
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func roundedRect(width: CGFloat, color: Color) -> some View {
        Rectangle().fill(color).frame(width: max(0, width))
    }

    // MARK: - 设置区

    private var settingsSection: some View {
        VStack(spacing: 0) {
            NavigationLink {
                NotificationSettingsView()
            } label: {
                CleanSettingsRow(icon: "bell.fill", color: .indigo, label: "每日提醒设置")
            }
            Divider().padding(.leading, 56)
            Button(action: { auth.logout() }) {
                CleanSettingsRow(icon: "rectangle.portrait.and.arrow.right", color: Color(red: 0.85, green: 0.3, blue: 0.75), label: "退出登录", isDestructive: true)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 数据

    @MainActor
    private func loadStats() async {
        loading = true
        if let s = try? await APIService.shared.fetchStats() { stats = s }
        loading = false
    }

    private func last7Days(_ data: [WeeklyItem]) -> [DayItem] {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let short = DateFormatter(); short.dateFormat = "MM/dd"
        let lookup = Dictionary(uniqueKeysWithValues: data.map { ($0.day, $0.count) })
        return (0..<7).reversed().map { offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            return DayItem(label: short.string(from: date), count: lookup[fmt.string(from: date)] ?? 0)
        }
    }
}

// MARK: - 子组件

struct MiniStatCard: View {
    let value: String; let label: String; let icon: String; let color: Color
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).font(.title3)
            Text(value).font(.system(.headline, design: .rounded, weight: .bold))
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct LegendItem: View {
    let color: Color; let label: String; let count: Int
    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text("\(label) \(count)").font(.caption2)
        }
    }
}

struct CleanSettingsRow: View {
    let icon: String; let color: Color; let label: String
    var isDestructive: Bool = false
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon).foregroundColor(color).font(.system(size: 15))
            }
            Text(label).foregroundColor(isDestructive ? color : .primary)
            Spacer()
            if !isDestructive {
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }
}

struct DayItem: Identifiable { let id = UUID(); let label: String; let count: Int }

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(red: Double((val >> 16) & 0xFF) / 255,
                  green: Double((val >> 8)  & 0xFF) / 255,
                  blue:  Double(val        & 0xFF) / 255)
    }
}
