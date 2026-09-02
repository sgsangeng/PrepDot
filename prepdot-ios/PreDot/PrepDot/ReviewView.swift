import SwiftUI

struct ReviewView: View {
    @Environment(AuthManager.self) var auth
    @Binding var selectedTab: Int
    @State private var plan: TodayPlan?
    @State private var loading = true
    @State private var sessionStarted = false
    @State private var currentIndex = 0
    @State private var sessionDone = false

    var pendingCards: [Flashcard] { plan?.cards ?? [] }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    loadingView
                } else if sessionDone || pendingCards.isEmpty {
                    DoneView(onGoToDecks: {
                        selectedTab = 1  // 切换到我的卡组
                        resetSession()
                    })
                    .navigationBarTitleDisplayMode(.inline)
                } else if sessionStarted {
                    CardSessionView(
                        cards: pendingCards,
                        currentIndex: $currentIndex,
                        onFinish: { sessionDone = true },
                        onCardChanged: applyCardUpdate
                    )
                    .navigationBarTitleDisplayMode(.inline)
                } else {
                    PlanOverviewView(plan: plan!, onStart: { sessionStarted = true })
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .task { await loadPlan() }
        }
    }

    private var loadingView: some View {
        ZStack {
            AnimatedAuroraBackground()
            ProgressView().tint(.white).scaleEffect(1.3)
        }
        .ignoresSafeArea()
    }

    private func loadPlan() async {
        loading = true
        do { plan = try await APIService.shared.fetchTodayPlan() } catch {}
        loading = false
    }

    /// 复习会话中编辑/加笔记后，原地更新当前计划里的卡片，不用重新拉计划
    private func applyCardUpdate(_ updated: Flashcard) {
        guard var p = plan,
              let idx = p.cards.firstIndex(where: { $0.id == updated.id }) else { return }
        p.cards[idx] = updated
        plan = p
    }

    private func resetSession() {
        sessionStarted = false; sessionDone = false; currentIndex = 0
        Task { await loadPlan() }
    }
}

// MARK: - 动态极光背景

struct AnimatedAuroraBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let dark = colorScheme == .dark
            GeometryReader { geo in
                ZStack {
                    // 背景底色：深色模式=深夜蓝，浅色模式=极淡薰衣草
                    (dark
                        ? Color(red: 0.04, green: 0.04, blue: 0.14)
                        : Color(red: 0.96, green: 0.95, blue: 1.00)
                    ).ignoresSafeArea()

                    // Blob 1 – indigo
                    Ellipse()
                        .fill(Color.indigo.opacity(dark ? 0.55 : 0.18))
                        .frame(width: geo.size.width * 0.9, height: geo.size.height * 0.5)
                        .blur(radius: 90)
                        .offset(x: geo.size.width  * CGFloat(sin(t * 0.28)) * 0.12,
                                y: geo.size.height * CGFloat(cos(t * 0.22)) * 0.08 - geo.size.height * 0.18)
                    // Blob 2 – purple
                    Ellipse()
                        .fill(Color.purple.opacity(dark ? 0.45 : 0.14))
                        .frame(width: geo.size.width * 0.7, height: geo.size.height * 0.45)
                        .blur(radius: 80)
                        .offset(x: geo.size.width  * CGFloat(cos(t * 0.33)) * 0.18,
                                y: geo.size.height * CGFloat(sin(t * 0.4))  * 0.12 + geo.size.height * 0.15)
                    // Blob 3 – pink
                    Ellipse()
                        .fill(Color(red: 0.85, green: 0.3, blue: 0.75).opacity(dark ? 0.3 : 0.12))
                        .frame(width: geo.size.width * 0.55, height: geo.size.height * 0.35)
                        .blur(radius: 70)
                        .offset(x: geo.size.width  * CGFloat(sin(t * 0.45 + 1)) * (-0.2),
                                y: geo.size.height * CGFloat(cos(t * 0.35 + 1)) * 0.1  + geo.size.height * 0.3)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 计划概览（全新设计）

struct PlanOverviewView: View {
    @Environment(\.colorScheme) var colorScheme
    let plan: TodayPlan
    let onStart: () -> Void

    private var textColor: Color { colorScheme == .dark ? .white : Color(red: 0.15, green: 0.05, blue: 0.35) }
    private var subColor:  Color { colorScheme == .dark ? .white.opacity(0.6) : Color(red: 0.3, green: 0.15, blue: 0.5).opacity(0.7) }

    var progress: Double {
        plan.totalCount == 0 ? 0 : Double(plan.completedCount) / Double(plan.totalCount)
    }
    var pending: Int { plan.cards.count }

    var body: some View {
        ZStack {
            AnimatedAuroraBackground()

            VStack(spacing: 0) {
                Spacer()

                // 标题
                VStack(spacing: 6) {
                    Text("今日复习")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(textColor)
                    Text(dateString())
                        .font(.subheadline)
                        .foregroundColor(subColor)
                }
                .padding(.bottom, 48)

                // 进度圆环
                ZStack {
                    // 轨道
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 14)
                        .frame(width: 220, height: 220)
                    // 进度弧
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(
                            AngularGradient(colors: [.indigo, Color(red: 0.7, green: 0.3, blue: 0.9), .pink],
                                            center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .frame(width: 220, height: 220)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.8), value: progress)
                    // 圆环内容
                    VStack(spacing: 4) {
                        Text("\(pending)")
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .foregroundColor(textColor)
                        Text("张待复习")
                            .font(.subheadline)
                            .foregroundColor(subColor)
                        if plan.totalCount > 0 {
                            Text("\(Int(progress * 100))% 完成")
                                .font(.caption)
                                .foregroundColor(subColor)
                                .padding(.top, 2)
                        }
                    }
                }

                // 统计信息
                HStack(spacing: 36) {
                    StatPill(icon: "checkmark.circle.fill",
                             value: "\(plan.completedCount)/\(plan.totalCount)",
                             label: "今日进度")
                    StatPill(icon: "clock.fill",
                             value: "≈\(plan.estimatedMinutes) 分钟",
                             label: "预计时间")
                }
                .padding(.top, 40)

                Spacer()

                // 开始按钮
                Button(action: onStart) {
                    HStack(spacing: 10) {
                        Text(pending == 0 ? "今日已完成" : "开始复习")
                            .font(.headline)
                        if pending > 0 {
                            Image(systemName: "arrow.right")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: 280)
                    .padding(.vertical, 18)
                    .background(
                        Group {
                            if pending == 0 {
                                Color.white.opacity(0.2)
                            } else {
                                LinearGradient(colors: [.indigo, Color(red: 0.55, green: 0.3, blue: 0.95)],
                                               startPoint: .leading, endPoint: .trailing)
                            }
                        }
                    )
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.indigo.opacity(0.5), radius: 16, y: 6)
                }
                .disabled(pending == 0)
                .padding(.bottom, 60)
            }
        }
    }

    private func dateString() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "M月d日 EEEE"
        return fmt.string(from: Date())
    }
}

struct StatPill: View {
    @Environment(\.colorScheme) var colorScheme
    let icon: String; let value: String; let label: String

    private var iconColor:  Color { colorScheme == .dark ? .white.opacity(0.8)  : Color(red: 0.3, green: 0.15, blue: 0.5).opacity(0.75) }
    private var valueColor: Color { colorScheme == .dark ? .white                : Color(red: 0.15, green: 0.05, blue: 0.35) }
    private var labelColor: Color { colorScheme == .dark ? .white.opacity(0.5)  : Color(red: 0.3, green: 0.15, blue: 0.5).opacity(0.55) }
    private var bgColor:    Color { colorScheme == .dark ? .white.opacity(0.1)  : Color(red: 0.55, green: 0.3, blue: 0.85).opacity(0.1) }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundColor(valueColor)
            Text(label)
                .font(.caption2)
                .foregroundColor(labelColor)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(bgColor, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 复习会话（保持原有逻辑，界面微调）

struct CardSessionView: View {
    let cards: [Flashcard]
    @Binding var currentIndex: Int
    let onFinish: () -> Void
    /// 卡片内容/笔记被修改后回调，用于原地刷新
    var onCardChanged: (Flashcard) -> Void = { _ in }

    @State private var flipped = false
    @State private var showRating = false
    @State private var submitting = false
    @State private var showChat = false
    @State private var showEdit = false
    @State private var showNote = false

    var current: Flashcard { cards[currentIndex] }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                HStack {
                    Text("\(currentIndex + 1) / \(cards.count)")
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Text("记忆度 \(current.memoryScore)")
                        .font(.caption).foregroundColor(.indigo)
                }
                ProgressView(value: Double(currentIndex + 1), total: Double(cards.count))
                    .tint(.indigo)
            }
            .padding(.horizontal)

            FlashcardView(card: current, flipped: $flipped)
                .onTapGesture { withAnimation(.spring()) { flipped.toggle() } }
                .onChange(of: flipped) { _, v in
                    withAnimation(.easeIn(duration: 0.2)) { showRating = v }
                }

            if showRating {
                VStack(spacing: 14) {
                    actionBar
                    RatingButtons(submitting: submitting) { submitRating($0) }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("点击卡片查看答案")
                    .font(.caption).foregroundColor(.secondary).padding(.bottom, 8)
            }
            Spacer()
        }
        .padding(.top)
        .onChange(of: currentIndex) { _, _ in flipped = false; showRating = false }
        .sheet(isPresented: $showChat) {
            CoachChatSheet(card: current)
        }
        .sheet(isPresented: $showEdit) {
            CardFormSheet(deckId: current.deckId, editing: current) { updated in
                onCardChanged(updated)
            }
        }
        .sheet(isPresented: $showNote) {
            CardNoteSheet(card: current) { updated in
                onCardChanged(updated)
            }
        }
    }

    // 翻面后的操作工具条：问AI / 编辑 / 笔记
    private var actionBar: some View {
        HStack(spacing: 12) {
            actionButton("问AI", "bubble.left.and.bubble.right.fill", .indigo) { showChat = true }
            actionButton("编辑", "pencil", .orange) { showEdit = true }
            actionButton("笔记", "note.text", .teal) { showNote = true }
        }
    }

    private func actionButton(_ label: String, _ icon: String,
                              _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption)
                Text(label).font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(color.opacity(0.1), in: Capsule())
            .foregroundColor(color)
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func submitRating(_ rating: String) {
        submitting = true
        Task {
            do { _ = try await APIService.shared.submitReview(ReviewRequest(cardId: current.id, rating: rating)) } catch {}
            submitting = false
            if currentIndex + 1 < cards.count { currentIndex += 1 } else { onFinish() }
        }
    }
}

// MARK: - 卡片组件

struct FlashcardView: View {
    let card: Flashcard
    @Binding var flipped: Bool

    var body: some View {
        ZStack {
            CardFace(card: card, isBack: false)
                .opacity(flipped ? 0 : 1)
                .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (0, 1, 0))
            CardFace(card: card, isBack: true)
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (0, 1, 0))
        }
        .frame(maxWidth: .infinity)
        // 高度随内容自适应：最短 260，最长 560（超长时答案区内部滚动）
        .frame(minHeight: 260, maxHeight: 560)
        .padding(.horizontal)
    }
}

struct CardFace: View {
    let card: Flashcard
    let isBack: Bool

    var hint: String { isBack ? "参考答案" : "点击翻转查看答案" }

    var body: some View {
        VStack(spacing: 12) {
            // 顶部：类型标记 + 提示
            HStack {
                if card.cardType != "qa" {
                    TypeBadge(label: card.cardType == "choice" ? "选择题" : "填空题",
                              color: card.cardType == "choice" ? .orange : .teal)
                }
                Spacer()
                Text(hint).font(.caption).foregroundColor(.secondary)
                    .textCase(.uppercase).tracking(0.8)
            }

            if isBack {
                backContent
            } else {
                Spacer()
                Text(card.question)
                    .font(.title3).fontWeight(.semibold)
                    .multilineTextAlignment(.center).lineSpacing(4)
                Spacer()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(isBack ? Color.indigo.opacity(0.1) : Color(UIColor.secondarySystemBackground))
                .overlay(RoundedRectangle(cornerRadius: 24)
                    .stroke(isBack ? Color.indigo.opacity(0.35) : Color.clear, lineWidth: 1.5))
        )
        .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
    }

    // 答案面：顶部保留问题（上下文），下方显示答案
    private var backContent: some View {
        VStack(spacing: 10) {
            // 问题（次要样式，翻面后依旧可见）
            Text(attributedQuestion)
                .font(.subheadline).fontWeight(.medium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center).lineSpacing(2)
                .lineLimit(3)

            Divider().padding(.horizontal, 8)

            // 答案：能放下就完整展示（卡片随之变高），放不下则内部滚动，保证不截断
            ViewThatFits(in: .vertical) {
                answerBlock
                ScrollView(showsIndicators: false) {
                    answerBlock
                        .padding(.vertical, 2)
                }
                .frame(maxHeight: 420)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // 答案主体：富文本 + 选择题选项
    private var answerBlock: some View {
        VStack(spacing: 10) {
            Text(attributedAnswer)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            if card.cardType == "choice" && !card.parsedOptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(card.parsedOptions.indices, id: \.self) { i in
                        let prefix = ["A", "B", "C", "D"][safe: i] ?? "\(i+1)"
                        let opt = card.parsedOptions[i]
                        HStack(spacing: 8) {
                            Text(prefix).font(.caption.bold())
                                .foregroundColor(opt == card.answer ? .white : .secondary)
                                .frame(width: 20, height: 20)
                                .background(opt == card.answer ? Color.indigo : Color.clear, in: Circle())
                            Text(opt).font(.caption).foregroundColor(opt == card.answer ? .indigo : .secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }

            // 我的笔记（独立于原始内容，仅当存在时显示）
            if let note = card.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.caption2).foregroundColor(.teal)
                        .padding(.top, 2)
                    Text(attributed(markdown: note))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // 富文本：把 **加粗** / *斜体* / `代码` 等 Markdown 转成局部样式，其余保持常规
    private var attributedAnswer: AttributedString {
        attributed(markdown: card.answer)
    }

    private var attributedQuestion: AttributedString {
        attributed(markdown: card.question)
    }

    private func attributed(markdown: String) -> AttributedString {
        if let attr = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attr
        }
        return AttributedString(markdown)   // 解析失败（如未闭合的 *）时退化为纯文本
    }
}

// MARK: - 评分

struct RatingButtons: View {
    let submitting: Bool; let onRate: (String) -> Void
    let ratings: [(String, String, String, Color)] = [
        ("Again","重新学","again",.red), ("Hard","明天","hard",.orange),
        ("Good","2-4天","good",.green), ("Easy","5-10天","easy",.indigo)
    ]
    var body: some View {
        HStack(spacing: 10) {
            ForEach(ratings, id: \.2) { label, sub, rating, color in
                Button { onRate(rating) } label: {
                    VStack(spacing: 3) {
                        Text(label).font(.system(.subheadline, weight: .bold))
                        Text(sub).font(.caption2)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(color.opacity(0.12)).foregroundColor(color)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.4), lineWidth: 1))
                }
                .disabled(submitting)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - 完成页（复用极光背景）

struct DoneView: View {
    @Environment(\.colorScheme) var colorScheme
    let onGoToDecks: () -> Void
    @State private var summary: ReviewSummary?
    @State private var loading = true

    private var titleColor: Color { colorScheme == .dark ? .white : Color(red: 0.15, green: 0.05, blue: 0.35) }
    private var subColor: Color   { colorScheme == .dark ? .white.opacity(0.7) : Color(red: 0.3, green: 0.15, blue: 0.5).opacity(0.75) }

    var body: some View {
        ZStack {
            AnimatedAuroraBackground()
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 64)

                    VStack(spacing: 20) {
                        Text("🎉").font(.system(size: 80))
                        Text("今日复习完成！")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(titleColor)
                        Text("你的记忆力正在不断增强\n明天继续加油！")
                            .multilineTextAlignment(.center)
                            .foregroundColor(subColor)
                            .font(.subheadline)
                    }

                    summarySection
                        .padding(.top, 32)

                    Spacer().frame(height: 40)

                    Button(action: onGoToDecks) {
                        Text("查看卡组")
                            .font(.headline)
                            .frame(maxWidth: 280)
                            .padding(.vertical, 18)
                            .background(colorScheme == .dark
                                ? Color.white.opacity(0.18)
                                : Color.indigo.opacity(0.12))
                            .foregroundColor(colorScheme == .dark ? .white : .indigo)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(
                                colorScheme == .dark ? Color.white.opacity(0.35) : Color.indigo.opacity(0.3),
                                lineWidth: 1.5))
                    }
                    // safeAreaInset 保证按钮不被 Tab Bar 遮挡
                    .padding(.bottom, 16)
                    .safeAreaPadding(.bottom)
                }
                .padding(.horizontal, 24)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await loadSummary() }
    }

    // MARK: - 今日小结卡片

    @ViewBuilder
    private var summarySection: some View {
        if loading {
            ProgressView()
                .tint(subColor)
                .padding(.vertical, 24)
        } else if let summary, !summary.decks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("今日小结")
                        .font(.headline)
                        .foregroundColor(titleColor)
                    Spacer()
                    Text("共 \(summary.totalCount) 张")
                        .font(.subheadline)
                        .foregroundColor(subColor)
                }
                Divider()
                    .overlay(colorScheme == .dark ? Color.white.opacity(0.2) : Color.indigo.opacity(0.15))
                ForEach(summary.decks) { deck in
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.subheadline)
                            .foregroundColor(.indigo)
                        Text(deck.deckTitle)
                            .font(.subheadline)
                            .foregroundColor(titleColor)
                            .lineLimit(1)
                        Spacer()
                        Text("\(deck.count) 张")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(subColor)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.2) : Color.white.opacity(0.8), lineWidth: 1)
            )
        }
    }

    private func loadSummary() async {
        loading = true
        do { summary = try await APIService.shared.fetchTodaySummary() } catch { summary = nil }
        loading = false
    }
}

// MARK: - AI 学习教练聊天（复习中随时提问）

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
    /// 教练本轮调用了哪些工具（用于展示可观测性）
    var toolNote: String? = nil
}

struct CoachChatSheet: View {
    let card: Flashcard
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var thinking = false

    private let quickQuestions = [
        "帮我讲透这道题",
        "面试官可能会怎么追问？",
        "出一道同考点的题目考考我"
    ]

    private let toolNameMap = [
        "WeakCardsTool": "薄弱卡片诊断",
        "ReviewTrendTool": "复习趋势统计",
        "NeglectedDecksTool": "冷落卡组检查",
        "GenerateSupplementCardsTool": "补强卡片生成"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contextBanner
                Divider()

                if messages.isEmpty {
                    introView
                } else {
                    messageList
                }

                inputBar
            }
            .navigationTitle("AI 学习教练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.large, .fraction(0.9)])
    }

    // 当前卡片上下文（让教练能针对这张卡回答，不编造）
    private var contextBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "rectangle.stack.fill")
                .font(.caption).foregroundColor(.indigo)
                .padding(.top, 2)
            Text(card.question)
                .font(.footnote).foregroundColor(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.indigo.opacity(0.06))
    }

    private var introView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("复习中有疑问？教练会根据你的真实学习数据（薄弱卡片、复习趋势等）回答，也能针对当前这张卡展开讲解。")
                    .font(.footnote).foregroundColor(.secondary)
                    .lineSpacing(4)
                Text("试试这样问：")
                    .font(.caption).foregroundColor(.secondary)
                ForEach(quickQuestions, id: \.self) { q in
                    Button {
                        send(q)
                    } label: {
                        HStack {
                            Text(q).font(.subheadline)
                            Spacer()
                            Image(systemName: "arrow.up.circle.fill").foregroundColor(.indigo)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(messages) { msg in
                        messageBubble(msg)
                            .id(msg.id)
                    }
                    if thinking {
                        thinkingRow
                            .id("thinking")
                    }
                }
                .padding(14)
            }
            .onChange(of: messages.count) { _, _ in
                if let lastId = messages.last?.id {
                    withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                }
            }
            .onChange(of: thinking) { _, v in
                if v { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
    }

    private func messageBubble(_ msg: ChatMessage) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 48) }
            VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: 5) {
                Text(msg.text)
                    .font(.subheadline)
                    .lineSpacing(3)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(
                        msg.role == .user ? Color.indigo : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .foregroundColor(msg.role == .user ? .white : .primary)
                if let note = msg.toolNote {
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            if msg.role == .assistant { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: msg.role == .user ? .trailing : .leading)
    }

    private var thinkingRow: some View {
        HStack {
            ProgressView().tint(.indigo)
            Text("教练正在分析你的复习数据…").font(.footnote).foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("输入你的疑问…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .submitLabel(.send)
                .onSubmit { send(input) }

            Button {
                send(input)
            } label: {
                Image(systemName: thinking ? "hourglass" : "arrow.up.circle.fill")
                    .font(.title2).foregroundColor(thinking ? .secondary : .indigo)
            }
            .disabled(thinking || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    // MARK: - 发送

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        input = ""
        messages.append(ChatMessage(role: .user, text: text))
        thinking = true
        Task {
            do {
                let run = try await APIService.shared.askCoach(buildPrompt(question: text))
                let reply = (run.output?.isEmpty == false) ? run.output! : "教练暂时没有给出有效回复（状态：\(run.status)）。"
                await MainActor.run {
                    messages.append(ChatMessage(role: .assistant, text: reply, toolNote: toolSummary(run)))
                    thinking = false
                }
            } catch {
                await MainActor.run {
                    messages.append(ChatMessage(role: .assistant,
                                                text: "😥 提问失败：\(error.localizedDescription)\n\n请确认后端已配置 AI API Key 后重试。"))
                    thinking = false
                }
            }
        }
    }

    /// 把当前卡片的问题/答案作为上下文拼进消息，让教练针对性回答
    private func buildPrompt(question: String) -> String {
        """
        我正在复习这张卡片：
        【问题】\(card.question)
        【答案】\(card.answer)

        我的疑问：\(question)
        """
    }

    private func toolSummary(_ run: AgentRun) -> String? {
        let tools = run.steps.filter { $0.stepType == "TOOL" }.compactMap { $0.toolName }
        let names = tools.map { toolNameMap[$0] ?? $0 }
        return names.isEmpty ? nil : "本次调用：\(names.joined(separator: "、"))"
    }
}

// MARK: - 卡片笔记（不动原始内容）

struct CardNoteSheet: View {
    let card: Flashcard
    let onSaved: (Flashcard) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("写给自己看的复习笔记，不会改动卡片的原始问题/答案。")
                    .font(.caption).foregroundColor(.secondary)

                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 220)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                HStack {
                    if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("清空") { text = "" }
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(text.count) 字")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding()
            .navigationTitle("卡片笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(saving)
                }
            }
            .onAppear { text = card.note ?? "" }
        }
    }

    private func save() {
        saving = true
        Task {
            do {
                let updated = try await APIService.shared.updateCardNote(id: card.id, note: text)
                onSaved(updated)
                dismiss()
            } catch {}
            saving = false
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
