import SwiftUI

// MARK: - 社区数据模型
struct CommunityPack: Decodable, Identifiable {
    let id: Int
    let title: String
    let category: String
    let description: String
    let cardCount: Int
    let tags: [String]
}

struct CommunityPackDetail: Decodable {
    let id: Int
    let title: String
    let category: String
    let description: String
    let cardCount: Int
    let tags: [String]
    let cards: [CommunityCardItem]
}

struct CommunityCardItem: Decodable {
    let question: String
    let answer: String
}

// MARK: - 社区主页
struct CommunityView: View {
    @State private var packs: [CommunityPack] = []
    @State private var loading = true
    @State private var selectedPack: CommunityPack?
    @State private var toastMsg: String?
    @State private var showToast = false

    let categoryColors: [String: Color] = [
        "Java": .orange, "Spring": .green, "数据库": .blue,
        "网络": .purple, "缓存": .red, "算法": .indigo
    ]

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("加载卡包库…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if packs.isEmpty {
                    ContentUnavailableView("暂无卡包", systemImage: "tray")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            // 顶部 Banner
                            bannerView

                            ForEach(packs) { pack in
                                PackRowView(
                                    pack: pack,
                                    color: categoryColors[pack.category] ?? .indigo
                                ) {
                                    selectedPack = pack
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("精选卡包")
            .task { await loadPacks() }
            .sheet(item: $selectedPack) { pack in
                PackDetailSheet(pack: pack) { msg in
                    selectedPack = nil
                    toastMsg = msg
                    showToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        showToast = false
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showToast, let msg = toastMsg {
                    Text(msg)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(), value: showToast)
        }
    }

    // Banner
    var bannerView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("精选卡包库")
                    .font(.title2.bold())
                Text("精心整理的面试知识点\n一键导入，立即复习")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
            }
            Spacer()
            Text("📚")
                .font(.system(size: 52))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(
                    colors: [Color.indigo.opacity(0.15), Color.purple.opacity(0.1)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.indigo.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func loadPacks() async {
        loading = true
        do {
            packs = try await APIService.shared.getCommunityPacks()
        } catch {}
        loading = false
    }
}

// MARK: - 卡包列表行
struct PackRowView: View {
    let pack: CommunityPack
    let color: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                // 分类色块
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.15))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Text(categoryEmoji(pack.category))
                            .font(.title2)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(pack.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(pack.cardCount) 张")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(color.opacity(0.15))
                            .foregroundColor(color)
                            .clipShape(Capsule())
                    }

                    Text(pack.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Tags
                    HStack(spacing: 6) {
                        ForEach(pack.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12))
                                .foregroundColor(.secondary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func categoryEmoji(_ category: String) -> String {
        switch category {
        case "Java": return "☕️"
        case "Spring": return "🌱"
        case "数据库": return "🗄️"
        case "网络": return "🌐"
        case "缓存": return "⚡️"
        case "算法": return "🧮"
        default: return "📖"
        }
    }
}

// MARK: - 卡包详情 Sheet
struct PackDetailSheet: View {
    let pack: CommunityPack
    let onImport: (String) -> Void

    @State private var detail: CommunityPackDetail?
    @State private var loading = true
    @State private var importing = false
    @State private var imported = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let detail = detail {
                    List {
                        // 描述
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(detail.description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 6) {
                                    ForEach(detail.tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.indigo.opacity(0.12))
                                            .foregroundColor(.indigo)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        // 卡片预览
                        Section("共 \(detail.cards.count) 张卡片") {
                            ForEach(Array(detail.cards.enumerated()), id: \.offset) { _, card in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Q: " + card.question)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(2)
                                    Text("A: " + card.answer)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(pack.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: doImport) {
                        if importing {
                            ProgressView().scaleEffect(0.8)
                        } else if imported {
                            Label("已导入", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("一键导入", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(importing || imported)
                }
            }
            .task { await loadDetail() }
        }
    }

    private func loadDetail() async {
        do {
            detail = try await APIService.shared.getCommunityPackDetail(id: pack.id)
        } catch {}
        loading = false
    }

    private func doImport() {
        importing = true
        Task {
            do {
                try await APIService.shared.importCommunityPack(id: pack.id)
                imported = true
                onImport("✅ 「\(pack.title)」已导入卡组")
            } catch {
                onImport("❌ 导入失败，请重试")
            }
            importing = false
        }
    }
}
