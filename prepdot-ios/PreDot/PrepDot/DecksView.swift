import SwiftUI

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct DecksView: View {
    @State private var decks: [Deck] = []
    @State private var loading = true
    @State private var showCreate = false
    @State private var showAIGenerate = false
    @State private var showCommunity = false
    @State private var selectedDeck: Deck?
    @State private var editingDeck: Deck?
    @State private var searchText = ""
    @State private var showGraph = false

    // 只显示根卡组（parentId == nil），子卡组在详情页里展开
    private var rootDecks: [Deck] { decks.filter { $0.parentId == nil } }

    // 搜索过滤
    private var filteredDecks: [Deck] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return rootDecks
        }
        let q = searchText.lowercased()
        return rootDecks.filter {
            $0.title.lowercased().contains(q) ||
            $0.category.lowercased().contains(q) ||
            ($0.description?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationSplitView {
            // ── 左侧/主列：卡组列表 ──
            Group {
                if loading {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if decks.isEmpty {
                    ContentUnavailableView(
                        "还没有卡组",
                        systemImage: "tray",
                        description: Text("点击右上角 + 新建第一个卡组")
                    )
                } else if filteredDecks.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(filteredDecks, selection: $selectedDeck) { deck in
                        DeckRow(deck: deck).tag(deck)
                            .swipeActions(edge: .leading) {
                                Button { editingDeck = deck } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(.indigo)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteDeck(deck)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, prompt: "搜索卡组名称或分类")
                }
            }
            .navigationTitle("我的卡组")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showGraph = true }) {
                        Label("知识图谱", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: { showCreate = true }) {
                            Label("手动新建卡组", systemImage: "plus.rectangle.on.folder")
                        }
                        Button(action: { showAIGenerate = true }) {
                            Label("AI 上传生成", systemImage: "sparkles")
                        }
                        Divider()
                        Button(action: { showCommunity = true }) {
                            Label("导入精选卡包", systemImage: "books.vertical.fill")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreate, onDismiss: loadDecks) {
                CreateDeckSheet()
            }
            .sheet(isPresented: $showAIGenerate, onDismiss: loadDecks) {
                AIGenerateView(onComplete: loadDecks)
            }
            .sheet(isPresented: $showCommunity) {
                CommunityView()
            }
            .sheet(item: $editingDeck, onDismiss: loadDecks) { deck in
                EditDeckSheet(deck: deck)
            }
            .fullScreenCover(isPresented: $showGraph) {
                NavigationStack { KnowledgeGraphView() }
            }
            .task { loadDecks() }

        } detail: {
            // ── 右侧/详情列：NavigationStack 保证子卡组有返回按钮
            NavigationStack {
                if let deck = selectedDeck {
                    DeckDetailView(deck: deck)
                } else {
                    ContentUnavailableView(
                        "选择一个卡组",
                        systemImage: "rectangle.stack",
                        description: Text("从左侧选择卡组查看卡片")
                    )
                }
            }
        }
    }

    private func loadDecks() {
        loading = true
        Task {
            do { decks = try await APIService.shared.fetchDecks() } catch {}
            loading = false
        }
    }

    private func deleteDeck(_ deck: Deck) {
        Task {
            do {
                try await APIService.shared.deleteDeck(id: deck.id)
                decks.removeAll { $0.id == deck.id }
                if selectedDeck?.id == deck.id { selectedDeck = nil }
            } catch {}
        }
    }
}

// MARK: - 编辑卡组 Sheet
struct EditDeckSheet: View {
    let deck: Deck
    @Environment(\.dismiss) var dismiss

    @State private var title       = ""
    @State private var category    = ""
    @State private var description = ""
    @State private var saving      = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("卡组名称", text: $title)
                    TextField("分类", text: $category)
                    TextField("描述（可选）", text: $description, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .navigationTitle("编辑卡组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                title       = deck.title
                category    = deck.category
                description = deck.description ?? ""
            }
        }
    }

    private func save() {
        saving = true
        Task {
            do {
                try await APIService.shared.updateDeck(
                    id: deck.id,
                    title: title.trimmingCharacters(in: .whitespaces),
                    category: category.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces)
                )
                dismiss()
            } catch {}
            saving = false
        }
    }
}

// MARK: - 卡组列表行
struct DeckRow: View {
    let deck: Deck

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(deck.title)
                    .font(.headline)
                Spacer()
                Text(deck.category)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.indigo.opacity(0.15))
                    .foregroundColor(.indigo)
                    .clipShape(Capsule())
            }

            if let desc = deck.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 20) {
                StatBadge(value: deck.cardCount, label: "卡片")
                StatBadge(value: deck.reviewedCount, label: "已复习")
                StatBadge(value: deck.avgMemoryScore, label: "记忆度")
                Spacer()
                // 记忆度进度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(scoreColor(deck.avgMemoryScore))
                            .frame(width: geo.size.width * CGFloat(deck.avgMemoryScore) / 100, height: 6)
                    }
                }
                .frame(width: 80, height: 6)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 0..<40:  return .red
        case 40..<70: return .orange
        default:      return .green
        }
    }
}

// MARK: - 卡组行统计徽章

struct StatBadge: View {
    let value: Int
    let label: String
    var body: some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 卡组详情页（卡片列表 or 子卡组列表）
struct DeckDetailView: View {
    let deck: Deck
    @State private var cards: [Flashcard] = []
    @State private var childDecks: [Deck] = []
    @State private var loading = true
    @State private var showCreate = false
    @State private var editingCard: Flashcard?
    @State private var isManaging = false
    @State private var selectedIds: Set<Int> = []
    @State private var showQuiz = false
    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if loading {
                    ProgressView()
                } else if !childDecks.isEmpty {
                    // 有子卡组（AI 生成的层级结构）→ 显示子卡组列表
                    List(childDecks) { child in
                        NavigationLink(destination: DeckDetailView(deck: child)) {
                            DeckRow(deck: child)
                        }
                    }
                    .listStyle(.insetGrouped)
                } else if cards.isEmpty {
                    ContentUnavailableView(
                        "还没有卡片",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("点击下方按钮添加第一张卡片")
                    )
                } else {
                    List(cards) { card in
                        CardRow(card: card, isManaging: isManaging,
                                isSelected: selectedIds.contains(card.id))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isManaging {
                                    if selectedIds.contains(card.id) { selectedIds.remove(card.id) }
                                    else { selectedIds.insert(card.id) }
                                } else {
                                    editingCard = card
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !isManaging {
                                    Button(role: .destructive) { deleteCard(card) } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if !isManaging {
                                    Button { editingCard = card } label: {
                                        Label("编辑", systemImage: "pencil")
                                    }.tint(.indigo)
                                }
                            }
                    }
                    .listStyle(.insetGrouped)
                    // 底部留出空间给悬浮按钮
                    .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
                }
            }

            // ── 底部悬浮操作栏
            if isManaging {
                HStack(spacing: 12) {
                    Button(role: .destructive, action: deleteBatch) {
                        Label("删除所选（\(selectedIds.count)）", systemImage: "trash")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedIds.isEmpty ? Color.red.opacity(0.3) : Color.red)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(selectedIds.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            } else {
                Button(action: { showCreate = true }) {
                    Label("添加卡片", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(Color.indigo)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: .indigo.opacity(0.35), radius: 8, y: 4)
                }
                .padding(.bottom, 16)
            }
        }
        .navigationTitle(deck.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 测验入口：叶卡组且卡片 ≥2 张时显示
            if childDecks.isEmpty && cards.count >= 2 && !isManaging {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showQuiz = true }) {
                        Label("测验", systemImage: "checklist")
                            .foregroundColor(.indigo)
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(isManaging ? "完成" : "管理") {
                    isManaging.toggle()
                    if !isManaging { selectedIds.removeAll() }
                }
                .fontWeight(isManaging ? .semibold : .regular)
                .foregroundColor(isManaging ? .indigo : .primary)
            }
        }
        .fullScreenCover(isPresented: $showQuiz) {
            QuizModeView(deck: deck, cards: cards)
        }
        .sheet(isPresented: $showCreate, onDismiss: loadCards) {
            CardFormSheet(deckId: deck.id)
        }
        .sheet(item: $editingCard, onDismiss: loadCards) { card in
            CardFormSheet(deckId: deck.id, editing: card)
        }
        .task(id: deck.id) { loadCards() }
    }

    private func loadCards() {
        loading = true
        Task {
            async let fetchedCards = APIService.shared.fetchCards(deckId: deck.id)
            async let fetchedChildren = APIService.shared.fetchChildDecks(parentId: deck.id)
            cards = (try? await fetchedCards) ?? []
            childDecks = (try? await fetchedChildren) ?? []
            loading = false
        }
    }

    private func deleteCard(_ card: Flashcard) {
        Task {
            do {
                try await APIService.shared.deleteCard(id: card.id)
                cards.removeAll { $0.id == card.id }
            } catch {}
        }
    }

    private func deleteBatch() {
        let ids = Array(selectedIds)
        Task {
            do {
                try await APIService.shared.deleteCards(ids: ids)
                cards.removeAll { selectedIds.contains($0.id) }
                selectedIds.removeAll()
                isManaging = false
            } catch {}
        }
    }
}

// MARK: - 卡片行
struct CardRow: View {
    let card: Flashcard
    var isManaging: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // 管理模式勾选圆
            if isManaging {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .indigo : .secondary.opacity(0.4))
                    .font(.title3)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    // 卡片类型徽标
                    if card.cardType == "choice" {
                        TypeBadge(label: "选择", color: .orange)
                    } else if card.cardType == "blank" {
                        TypeBadge(label: "填空", color: .teal)
                    }
                    Text(card.question).font(.headline).lineLimit(2)
                }

                // 选择题展示选项
                if card.cardType == "choice" && !card.parsedOptions.isEmpty {
                    let opts = card.parsedOptions
                    ForEach(opts.indices, id: \.self) { i in
                        let prefix = ["A", "B", "C", "D"][safe: i] ?? "\(i+1)"
                        Text("\(prefix). \(opts[i])")
                            .font(.caption)
                            .foregroundColor(opts[i] == card.answer ? .green : .secondary)
                    }
                } else {
                    Text(card.answer)
                        .font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                }

                HStack(spacing: 12) {
                    Label("\(card.memoryScore)", systemImage: "brain")
                        .font(.caption).foregroundColor(.indigo)
                    Text("复习 \(card.reviewCount) 次")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct TypeBadge: View {
    let label: String; let color: Color
    var body: some View {
        Text(label)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// MARK: - 新建 / 编辑卡片 Sheet（支持问答 / 选择题 / 填空）
struct CardFormSheet: View {
    let deckId: Int
    var editing: Flashcard? = nil

    @Environment(\.dismiss) var dismiss

    enum CardMode: String, CaseIterable {
        case qa     = "问答"
        case choice = "选择题"
        case blank  = "填空"
    }

    @State private var mode: CardMode = .qa
    @State private var question  = ""
    @State private var answer    = ""
    // 选择题
    @State private var optionA = ""; @State private var optionB = ""
    @State private var optionC = ""; @State private var optionD = ""
    @State private var correctIndex = 0
    @State private var saving = false

    var isEdit: Bool { editing != nil }

    private var canSave: Bool {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return false }
        switch mode {
        case .qa, .blank:
            return !answer.trimmingCharacters(in: .whitespaces).isEmpty
        case .choice:
            return !optionA.isEmpty && !optionB.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── 类型选择
                Section {
                    Picker("卡片类型", selection: $mode) {
                        ForEach(CardMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isEdit)   // 编辑时不允许改类型
                } footer: {
                    switch mode {
                    case .qa:     Text("正面写问题，背面写答案，复习时翻转查看")
                    case .choice: Text("设置 2-4 个选项，选择正确答案，复习时作为单选题")
                    case .blank:  Text("用 ____ 表示填空位，复习时输入答案填空")
                    }
                }

                // ── 问题
                Section("问题") {
                    if mode == .blank {
                        TextEditor(text: $question).frame(minHeight: 80)
                        Button(action: { question += "____" }) {
                            Label("插入填空符 ____", systemImage: "square.and.pencil")
                                .font(.caption).foregroundColor(.indigo)
                        }
                    } else {
                        TextField("输入问题", text: $question, axis: .vertical).lineLimit(3...6)
                    }
                }

                // ── 类型相关内容
                switch mode {
                case .qa:
                    Section("答案") {
                        TextField("输入答案", text: $answer, axis: .vertical).lineLimit(4...10)
                    }
                case .choice:
                    Section("选项（至少填 A、B）") {
                        optionField("A", text: $optionA, index: 0)
                        optionField("B", text: $optionB, index: 1)
                        optionField("C（选填）", text: $optionC, index: 2)
                        optionField("D（选填）", text: $optionD, index: 3)
                    }
                case .blank:
                    Section("填空答案") {
                        TextField("按顺序填写答案，多个答案用分号分隔", text: $answer, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }
            }
            .navigationTitle(isEdit ? "编辑卡片" : "新建卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "保存" : "添加") { save() }
                        .disabled(!canSave || saving)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { prefill() }
        }
    }

    private func optionField(_ label: String, text: Binding<String>, index: Int) -> some View {
        HStack(spacing: 10) {
            // 正确答案选择器
            Button {
                correctIndex = index
            } label: {
                Image(systemName: correctIndex == index ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(correctIndex == index ? .green : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            TextField(label, text: text)
        }
    }

    private func prefill() {
        guard let card = editing else { return }
        question = card.question
        answer   = card.answer
        mode     = CardMode(rawValue: card.cardType) ?? .qa
        if mode == .choice {
            let opts = card.parsedOptions
            optionA = opts[safe: 0] ?? ""
            optionB = opts[safe: 1] ?? ""
            optionC = opts[safe: 2] ?? ""
            optionD = opts[safe: 3] ?? ""
            correctIndex = opts.firstIndex(of: card.answer) ?? 0
        }
    }

    private func save() {
        saving = true
        Task {
            do {
                let (finalAnswer, optionsJson) = buildPayload()
                if let card = editing {
                    try await APIService.shared.updateCard(
                        id: card.id, question: question, answer: finalAnswer,
                        cardType: mode.rawValue, options: optionsJson)
                } else {
                    try await APIService.shared.createCard(
                        deckId: deckId, question: question, answer: finalAnswer,
                        cardType: mode.rawValue, options: optionsJson)
                }
                dismiss()
            } catch {}
            saving = false
        }
    }

    /// 根据模式构造 answer 和 options JSON
    private func buildPayload() -> (answer: String, options: String?) {
        switch mode {
        case .qa, .blank:
            return (answer, nil)
        case .choice:
            var opts = [optionA, optionB]
            if !optionC.isEmpty { opts.append(optionC) }
            if !optionD.isEmpty { opts.append(optionD) }
            let correctAnswer = opts[safe: correctIndex] ?? opts[0]
            let json = (try? String(data: JSONEncoder().encode(opts), encoding: .utf8)) ?? "[]"
            return (correctAnswer, json)
        }
    }
}

// MARK: - 新建卡组 Sheet
struct CreateDeckSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var category = "综合"
    @State private var description = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("卡组名称（必填）", text: $title)
                    TextField("分类", text: $category)
                    TextField("描述（可选）", text: $description, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .navigationTitle("新建卡组")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { create() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func create() {
        saving = true
        Task {
            do {
                _ = try await APIService.shared.createDeck(
                    CreateDeckRequest(title: title, category: category, description: description)
                )
                dismiss()
            } catch {}
            saving = false
        }
    }
}

