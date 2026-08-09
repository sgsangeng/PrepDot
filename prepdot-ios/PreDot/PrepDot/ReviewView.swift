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
                        onFinish: { sessionDone = true }
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

    @State private var flipped = false
    @State private var showRating = false
    @State private var submitting = false

    var current: Flashcard { cards[currentIndex] }

    var body: some View {
        VStack(spacing: 24) {
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
                RatingButtons(submitting: submitting) { submitRating($0) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("点击卡片查看答案")
                    .font(.caption).foregroundColor(.secondary).padding(.bottom, 8)
            }
            Spacer()
        }
        .padding(.top)
        .onChange(of: currentIndex) { _, _ in flipped = false; showRating = false }
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
        .frame(maxWidth: .infinity).frame(height: 260).padding(.horizontal)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Text(card.question)
                .font(.subheadline).fontWeight(.medium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center).lineSpacing(2)
                .lineLimit(3)

            Divider().padding(.horizontal, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    Text(card.answer)
                        .font(.title3).fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center).lineSpacing(4)
                        .frame(maxWidth: .infinity)

                    // 选择题选项
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
                }
            }
        }
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

    private var titleColor: Color { colorScheme == .dark ? .white : Color(red: 0.15, green: 0.05, blue: 0.35) }
    private var subColor: Color   { colorScheme == .dark ? .white.opacity(0.7) : Color(red: 0.3, green: 0.15, blue: 0.5).opacity(0.75) }

    var body: some View {
        ZStack {
            AnimatedAuroraBackground()
            VStack(spacing: 0) {
                Spacer()
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
                Spacer()
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
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
