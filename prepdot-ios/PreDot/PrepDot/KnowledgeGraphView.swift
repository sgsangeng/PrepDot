import SwiftUI

// MARK: - 布局节点

private struct GNode: Identifiable {
    let id: String
    let label: String
    let isRoot: Bool
    let memoryScore: Int
    let reviewCount: Int
    var pos: CGPoint = .zero          // 相对图心坐标
    let wobble: Double = Double.random(in: 0 ..< 2 * .pi)
}

private struct GEdge {
    let source: String
    let target: String
}

/// 单个卡组的图谱数据
private struct DeckGraph: Identifiable {
    let id: Int          // 根卡组 id
    let title: String
    var nodes: [GNode]
    var edges: [GEdge]
}

// MARK: - 知识图谱整页视图（每卡组一张独立图）

struct KnowledgeGraphView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var graphs:   [DeckGraph] = []
    @State private var selectedGraphIndex = 0
    @State private var loading   = true
    @State private var errorMsg  = ""
    @State private var selectedNode: GNode? = nil
    @State private var appeared  = false

    @State private var pan:      CGSize  = .zero
    @State private var lastPan:  CGSize  = .zero
    @State private var zoom:     CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0

    private var currentGraph: DeckGraph? {
        graphs.indices.contains(selectedGraphIndex) ? graphs[selectedGraphIndex] : nil
    }

    // MARK: - 辅助

    private func toScreen(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width  / 2 + (p.x + pan.width)  * zoom,
            y: size.height / 2 + (p.y + pan.height) * zoom
        )
    }

    private func radius(for n: GNode) -> CGFloat {
        n.isRoot ? 30 : 20 + CGFloat(min(n.reviewCount, 30)) * 0.4
    }

    private func color(for n: GNode) -> Color {
        let t = CGFloat(max(0, min(100, n.memoryScore))) / 100.0
        return Color(red: 0.85 - t * 0.50, green: 0.38 - t * 0.10, blue: 0.82 + t * 0.14)
    }

    // MARK: - body

    var body: some View {
        VStack(spacing: 0) {
            if !graphs.isEmpty && !loading {
                deckPicker
            }

            GeometryReader { geo in
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()

                    if loading {
                        loadingView
                    } else if !errorMsg.isEmpty {
                        ContentUnavailableView("加载失败",
                                               systemImage: "exclamationmark.triangle.fill",
                                               description: Text(errorMsg))
                    } else if graphs.isEmpty {
                        ContentUnavailableView("暂无图谱",
                                               systemImage: "point.3.connected.trianglepath.dotted",
                                               description: Text("添加卡组后将自动生成"))
                    } else if let g = currentGraph {
                        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                            graphCanvas(graph: g, in: geo.size,
                                        t: ctx.date.timeIntervalSinceReferenceDate)
                        }
                        .scaleEffect(appeared ? 1.0 : 0.85)
                        .opacity(appeared ? 1.0 : 0)
                        .id(g.id)   // 切换卡组时重新触发入场
                    }

                    if !graphs.isEmpty && !loading {
                        legend
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: .bottomTrailing)
                    }
                }
            }

            if let sel = selectedNode {
                detailPanel(sel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedNode?.id)
        .navigationTitle("知识图谱")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .task { await load() }
        .onChange(of: loading) { _, val in
            if !val && !graphs.isEmpty { triggerAppear() }
        }
    }

    private func triggerAppear() {
        appeared = false
        withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
            appeared = true
        }
    }

    // MARK: - 卡组选择器（横向 pills）

    private var deckPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(graphs.enumerated()), id: \.element.id) { idx, g in
                        let isSel = idx == selectedGraphIndex
                        Button {
                            guard idx != selectedGraphIndex else { return }
                            selectedNode = nil
                            resetView()
                            selectedGraphIndex = idx
                            triggerAppear()
                            withAnimation { proxy.scrollTo(g.id, anchor: .center) }
                        } label: {
                            Text(g.title)
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
                        .id(g.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 加载动画

    private var loadingView: some View {
        VStack(spacing: 18) {
            ZStack {
                ForEach(0 ..< 3) { i in
                    Circle()
                        .stroke(Color.indigo.opacity(0.18 - Double(i) * 0.04), lineWidth: 1.5)
                        .frame(width: CGFloat(52 + i * 26), height: CGFloat(52 + i * 26))
                }
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 22)).foregroundColor(.indigo)
            }
            Text("构建知识图谱…").font(.headline)
            ProgressView().tint(.indigo)
        }
    }

    // MARK: - 图谱画布（单卡组）

    private func graphCanvas(graph g: DeckGraph, in size: CGSize, t: Double) -> some View {
        ZStack {
            // ── 直线连接
            Canvas { ctx, sz in
                for e in g.edges {
                    guard let src = g.nodes.first(where: { $0.id == e.source }),
                          let tgt = g.nodes.first(where: { $0.id == e.target }) else { continue }
                    let sp = toScreen(wobbled(src, t: t), in: sz)
                    let tp = toScreen(wobbled(tgt, t: t), in: sz)
                    var path = Path()
                    path.move(to: sp)
                    path.addLine(to: tp)
                    ctx.stroke(path,
                               with: .color(Color.indigo.opacity(0.3)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }

            // ── 节点
            ForEach(g.nodes) { n in
                let sp  = toScreen(wobbled(n, t: t), in: size)
                let r   = radius(for: n)
                let c   = color(for: n)
                let sel = selectedNode?.id == n.id

                Circle()
                    .fill(c)
                    .frame(width: r * 2, height: r * 2)
                    .overlay(Circle().stroke(
                        sel ? Color.white : Color.white.opacity(0.4),
                        lineWidth: sel ? 2.5 : 1.2
                    ))
                    .shadow(color: c.opacity(sel ? 0.55 : 0.2),
                            radius: sel ? 12 : 4, y: 2)
                    .scaleEffect(sel ? 1.18 : 1.0)
                    .animation(.spring(response: 0.22, dampingFraction: 0.7), value: sel)
                    .position(sp)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                            selectedNode = selectedNode?.id == n.id ? nil : n
                        }
                    }

                Text(n.label)
                    .font(.system(size: n.isRoot ? 13 : 11,
                                  weight: n.isRoot ? .semibold : (sel ? .semibold : .regular)))
                    .foregroundColor(sel || n.isRoot ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 96)
                    .shadow(color: Color(.systemBackground).opacity(0.9), radius: 5)
                    .shadow(color: Color(.systemBackground).opacity(0.9), radius: 5)
                    .position(CGPoint(x: sp.x, y: sp.y + r + 14))
            }
        }
        .gesture(
            SimultaneousGesture(
                DragGesture()
                    .onChanged { v in
                        pan = CGSize(
                            width:  lastPan.width  + v.translation.width  / zoom,
                            height: lastPan.height + v.translation.height / zoom
                        )
                    }
                    .onEnded { _ in lastPan = pan },
                MagnificationGesture()
                    .onChanged { v in zoom = max(0.4, min(4.0, lastZoom * v)) }
                    .onEnded   { _ in lastZoom = zoom }
            )
        )
    }

    private func wobbled(_ n: GNode, t: Double) -> CGPoint {
        CGPoint(
            x: n.pos.x + CGFloat(sin(t * 0.42 + n.wobble)) * 2.0,
            y: n.pos.y + CGFloat(cos(t * 0.33 + n.wobble)) * 1.5
        )
    }

    private func resetView() {
        pan = .zero; lastPan = .zero
        zoom = 1.0; lastZoom = 1.0
    }

    // MARK: - 详情面板

    private func detailPanel(_ n: GNode) -> some View {
        let neighbors = (currentGraph?.edges ?? []).compactMap { e -> String? in
            if e.source == n.id { return currentGraph?.nodes.first { $0.id == e.target }?.label }
            if e.target == n.id { return currentGraph?.nodes.first { $0.id == e.source }?.label }
            return nil
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(color(for: n)).frame(width: 9, height: 9)
                Text(n.isRoot ? "卡组" : "子主题")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("记忆度 \(n.memoryScore)%")
                    .font(.caption2)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(color(for: n).opacity(0.15), in: Capsule())
                    .foregroundColor(color(for: n))
                Button { withAnimation { selectedNode = nil } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary).font(.title3)
                }
            }
            Text(n.label).font(.subheadline.bold())
            if !neighbors.isEmpty {
                Divider()
                Text(n.isRoot ? "涵盖子主题" : "所属卡组")
                    .font(.caption).foregroundColor(.secondary)
                MiniTagFlow(labels: neighbors)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.07), radius: 8, y: -2)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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
        loading = true; errorMsg = ""; appeared = false
        do {
            let decks = try await APIService.shared.fetchDecks()
            guard !decks.isEmpty else {
                await MainActor.run { loading = false }
                return
            }
            let built = buildGraphs(decks: decks)
            await MainActor.run {
                graphs = built
                selectedGraphIndex = 0
                loading = false
            }
        } catch {
            await MainActor.run { errorMsg = error.localizedDescription; loading = false }
        }
    }

    // MARK: - 构建每卡组独立图谱（放射状布局）

    private func buildGraphs(decks: [Deck]) -> [DeckGraph] {
        let rootDecks  = decks.filter { $0.parentId == nil }
        let childDecks = decks.filter { $0.parentId != nil }

        return rootDecks.map { root in
            var nodes: [GNode] = []
            var edges: [GEdge] = []

            let rootId = "d-\(root.id)"
            var rootNode = GNode(id: rootId, label: root.title, isRoot: true,
                                 memoryScore: root.avgMemoryScore,
                                 reviewCount: root.reviewedCount)
            rootNode.pos = .zero          // 根节点居中
            nodes.append(rootNode)

            let children = childDecks.filter { $0.parentId == root.id }
            let count    = children.count
            // 半径随子节点数量增加，避免拥挤
            let ringR: CGFloat = count <= 6 ? 150 : 150 + CGFloat(count - 6) * 12

            for (i, child) in children.enumerated() {
                let angle = 2 * Double.pi * Double(i) / Double(max(count, 1)) - Double.pi / 2
                var cn = GNode(id: "d-\(child.id)", label: child.title, isRoot: false,
                               memoryScore: child.avgMemoryScore,
                               reviewCount: child.reviewedCount)
                cn.pos = CGPoint(x: ringR * cos(angle), y: ringR * sin(angle))
                nodes.append(cn)
                edges.append(GEdge(source: rootId, target: cn.id))
            }

            return DeckGraph(id: root.id, title: root.title, nodes: nodes, edges: edges)
        }
    }
}

// MARK: - 标签流

private struct MiniTagFlow: View {
    let labels: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], alignment: .leading, spacing: 5) {
            ForEach(labels, id: \.self) { lbl in
                Text(lbl)
                    .font(.caption2)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.indigo.opacity(0.1), in: Capsule())
                    .foregroundColor(.indigo)
                    .lineLimit(1)
            }
        }
    }
}
