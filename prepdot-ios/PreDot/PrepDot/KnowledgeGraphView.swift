import SwiftUI
import Foundation

// MARK: - 掌握度散点图
//
// 每个点代表一张卡片：
// - X 轴 = FSRS 难度 difficulty（1-10）
// - Y 轴 = FSRS 稳定性 stability（天，log 刻度）
// - 颜色 = 实时掌握度 retrievability（浅粉→深紫）
//
// 点落在右上角 = 简单 + 稳定 = 已掌握；左下角 = 难 + 不稳 = 需抢救。
// 相比原来的力导向卡组层级图，这里不用 AI 语义边，也不跑力导向迭代，
// 位置直接由 FSRS 状态映射，一张图就能看出整个卡组的记忆健康度。

struct KnowledgeGraphView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var rootDecks: [Deck] = []
    @State private var selectedRootIndex = 0
    @State private var cards: [Flashcard] = []

    @State private var loading = true          // 卡组列表加载
    @State private var cardsLoading = false     // 卡片加载
    @State private var errorMsg = ""
    @State private var selectedCard: Flashcard? = nil

    // MARK: - 派生数据

    /// 只绘制已经复习过（有 difficulty/stability）的卡片
    private var plotCards: [Flashcard] {
        cards.filter { $0.difficulty != nil && $0.stability != nil }
    }

    /// log10(稳定性) 的范围，用于 Y 轴归一化
    private var logStabilityRange: (min: Double, max: Double) {
        let logs = plotCards.map { log10(max($0.stability ?? 0.01, 0.01)) }
        guard let mn = logs.min(), let mx = logs.max() else { return (0, 1) }
        if mn == mx { return (mn - 0.5, mx + 0.5) }
        return (mn, mx)
    }

    // MARK: - 坐标与颜色

    private func plotArea(in size: CGSize) -> CGRect {
        let padX: CGFloat = 46
        let padTop: CGFloat = 16
        let padBottom: CGFloat = 34
        return CGRect(x: padX, y: padTop,
                      width: max(size.width - padX * 2, 0),
                      height: max(size.height - padTop - padBottom, 0))
    }

    /// 由 id 派生的确定性抖动（0-1），用来摊开重合的点，避免同一状态的卡片叠成一坨
    private func jitter(for id: Int) -> CGPoint {
        func hash(_ seed: Double) -> Double {
            let s = sin(seed) * 43758.5453
            return s - floor(s)          // 0..1
        }
        let jx = (hash(Double(id) * 12.9898) - 0.5) * 2   // -1..1
        let jy = (hash(Double(id) * 78.233)  - 0.5) * 2
        return CGPoint(x: CGFloat(jx) * 6, y: CGFloat(jy) * 6)   // ±6pt
    }

    private func point(for card: Flashcard, in size: CGSize) -> CGPoint {
        let area = plotArea(in: size)
        let d = card.difficulty ?? 5.0
        let s = max(card.stability ?? 0.01, 0.01)
        let logS = log10(s)
        let (mn, mx) = logStabilityRange

        let nx = min(max((d - 1.0) / 9.0, 0), 1)                       // 难度 1-10 → 0-1
        let ny = min(max((logS - mn) / max(mx - mn, 0.001), 0), 1)     // log 稳定性 → 0-1

        let j = jitter(for: card.id)
        let x = area.minX + CGFloat(nx) * area.width + j.x
        let y = area.maxY - CGFloat(ny) * area.height + j.y            // 反向：高稳定性在顶部
        return CGPoint(x: x, y: y)
    }

    private func color(forScore score: Int) -> Color {
        let t = CGFloat(max(0, min(100, score))) / 100.0
        return Color(red: 0.85 - t * 0.50, green: 0.38 - t * 0.10, blue: 0.82 + t * 0.14)
    }

    // MARK: - body

    var body: some View {
        VStack(spacing: 0) {
            if !rootDecks.isEmpty && !loading {
                deckPicker
                statsBar
            }

            GeometryReader { geo in
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()

                    if loading || cardsLoading {
                        loadingView
                    } else if !errorMsg.isEmpty {
                        ContentUnavailableView("加载失败",
                                               systemImage: "exclamationmark.triangle.fill",
                                               description: Text(errorMsg))
                    } else if rootDecks.isEmpty {
                        ContentUnavailableView("暂无卡组",
                                               systemImage: "square.grid.2x2",
                                               description: Text("先创建卡组，再回来查看掌握度地图"))
                    } else if cards.isEmpty {
                        ContentUnavailableView("该卡组暂无卡片",
                                               systemImage: "rectangle.stack",
                                               description: Text("添加卡片并完成首次复习后，这里会出现掌握度分布"))
                    } else if plotCards.isEmpty {
                        ContentUnavailableView("还没有复习记录",
                                               systemImage: "sparkles",
                                               description: Text("完成第一次复习后，卡片会按难度/稳定性出现在图上"))
                    } else {
                        scatter(in: geo.size)
                    }

                    if !plotCards.isEmpty && !loading && !cardsLoading {
                        legend
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: .bottomTrailing)
                    }
                }
            }

            if let sel = selectedCard {
                detailPanel(sel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedCard?.id)
        .navigationTitle("掌握度地图")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .task { await load() }
        .onChange(of: selectedRootIndex) { _, newIdx in
            if rootDecks.indices.contains(newIdx) {
                selectedCard = nil
                Task { await loadCards(for: rootDecks[newIdx]) }
            }
        }
    }

    // MARK: - 卡组选择器（横向 pills）

    private var deckPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(rootDecks.enumerated()), id: \.element.id) { idx, deck in
                        let isSel = idx == selectedRootIndex
                        Button {
                            guard idx != selectedRootIndex else { return }
                            withAnimation { proxy.scrollTo(deck.id, anchor: .center) }
                            selectedRootIndex = idx
                        } label: {
                            Text(deck.title)
                                .font(.subheadline.weight(isSel ? .semibold : .regular))
                                .foregroundColor(isSel ? .white : .primary)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(
                                    isSel ? AnyShapeStyle(LinearGradient(
                                        colors: [.indigo, .purple],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                          : AnyShapeStyle(Color(.secondarySystemBackground)),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .id(deck.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Color(.systemBackground))
    }

    private var statsBar: some View {
        HStack(spacing: 14) {
            Label("已复习 \(plotCards.count) / \(cards.count) 张", systemImage: "checkmark.circle")
            Spacer()
            if plotCards.count < cards.count {
                Text("\(cards.count - plotCards.count) 张待复习")
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    // MARK: - 加载动画

    private var loadingView: some View {
        VStack(spacing: 18) {
            ProgressView().tint(.indigo)
            Text("生成掌握度地图…").font(.headline)
        }
    }

    // MARK: - 散点画布

    private func scatter(in size: CGSize) -> some View {
        let area = plotArea(in: size)
        return ZStack {
            // 网格 + 坐标轴
            Canvas { ctx, _ in
                for i in 0...4 {
                    let fx = area.minX + area.width * CGFloat(i) / 4
                    var v = Path()
                    v.move(to: CGPoint(x: fx, y: area.minY))
                    v.addLine(to: CGPoint(x: fx, y: area.maxY))
                    ctx.stroke(v, with: .color(Color(.systemGray5)), lineWidth: 0.5)

                    let fy = area.minY + area.height * CGFloat(i) / 4
                    var h = Path()
                    h.move(to: CGPoint(x: area.minX, y: fy))
                    h.addLine(to: CGPoint(x: area.maxX, y: fy))
                    ctx.stroke(h, with: .color(Color(.systemGray5)), lineWidth: 0.5)
                }
                var ax = Path()
                ax.move(to: CGPoint(x: area.minX, y: area.maxY))
                ax.addLine(to: CGPoint(x: area.maxX, y: area.maxY))
                ctx.stroke(ax, with: .color(Color.secondary.opacity(0.5)), lineWidth: 1)

                var ay = Path()
                ay.move(to: CGPoint(x: area.minX, y: area.minY))
                ay.addLine(to: CGPoint(x: area.minX, y: area.maxY))
                ctx.stroke(ay, with: .color(Color.secondary.opacity(0.5)), lineWidth: 1)
            }

            // 轴标签
            Text("难度 →").font(.caption2).foregroundColor(.secondary)
                .position(x: area.maxX - 20, y: area.maxY + 14)
            Text("稳定性 ↑").font(.caption2).foregroundColor(.secondary)
                .rotationEffect(.degrees(-90))
                .position(x: area.minX - 16, y: area.midY)

            // 节点
            ForEach(plotCards) { card in
                node(card, in: size)
            }
        }
    }

    private func node(_ card: Flashcard, in size: CGSize) -> some View {
        let p = point(for: card, in: size)
        let c = color(forScore: card.memoryScore)
        let sel = selectedCard?.id == card.id
        return Circle()
            .fill(c.opacity(sel ? 1.0 : 0.72))
            .frame(width: sel ? 22 : 14, height: sel ? 22 : 14)
            .overlay(Circle().stroke(sel ? Color.white : Color.clear, lineWidth: 2))
            .shadow(color: c.opacity(sel ? 0.5 : 0.15), radius: sel ? 8 : 3)
            .scaleEffect(sel ? 1.15 : 1.0)
            .position(p)
            .onTapGesture {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                    selectedCard = selectedCard?.id == card.id ? nil : card
                }
            }
    }

    // MARK: - 详情面板

    private func detailPanel(_ card: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(color(forScore: card.memoryScore)).frame(width: 9, height: 9)
                Text("掌握度 \(card.memoryScore)%")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button { withAnimation { selectedCard = nil } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary).font(.title3)
                }
            }
            Text(card.question).font(.subheadline.bold()).lineLimit(4)
            HStack(spacing: 16) {
                stat("难度", String(format: "%.1f", card.difficulty ?? 0))
                stat("稳定性", String(format: "%.1f 天", card.stability ?? 0))
                stat("复习", "\(card.reviewCount) 次")
                stat("类型", card.cardType)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.07), radius: 8, y: -2)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.caption.weight(.semibold))
        }
    }

    // MARK: - 图例

    private var legend: some View {
        VStack(alignment: .trailing, spacing: 4) {
            legendRow(color: Color(red: 0.85, green: 0.38, blue: 0.82), label: "待加强")
            legendRow(color: Color(red: 0.55, green: 0.30, blue: 0.88), label: "进行中")
            legendRow(color: Color(red: 0.35, green: 0.28, blue: 0.96), label: "已掌握")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9))
        }
    }

    // MARK: - 数据加载

    private func load() async {
        loading = true; errorMsg = ""
        do {
            let all = try await APIService.shared.fetchDecks()
            let roots = all.filter { $0.parentId == nil }
            await MainActor.run {
                rootDecks = roots
                loading = false
                if !roots.isEmpty {
                    selectedRootIndex = 0
                    Task { await loadCards(for: roots[0]) }
                }
            }
        } catch {
            await MainActor.run { errorMsg = error.localizedDescription; loading = false }
        }
    }

    private func loadCards(for deck: Deck) async {
        cardsLoading = true; errorMsg = ""
        do {
            let c = try await APIService.shared.fetchCardsDeep(deckId: deck.id)
            await MainActor.run {
                cards = c
                selectedCard = nil
                cardsLoading = false
            }
        } catch {
            await MainActor.run { errorMsg = error.localizedDescription; cardsLoading = false }
        }
    }
}
