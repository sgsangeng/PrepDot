import SwiftUI

// MARK: - 选择题模式入口（从 DeckDetailView 触发）
struct QuizModeView: View {
    let deck: Deck
    let cards: [Flashcard]

    @Environment(\.dismiss) var dismiss

    // 生成选择题（每题4选项）
    @State private var questions: [QuizQuestion] = []
    @State private var current   = 0
    @State private var selected: Int? = nil      // 用户选的选项索引
    @State private var showAnswer = false
    @State private var correctCount = 0
    @State private var finished = false

    var body: some View {
        NavigationStack {
            Group {
                if cards.count < 2 {
                    ContentUnavailableView(
                        "卡片不足",
                        systemImage: "exclamationmark.triangle",
                        description: Text("选择题至少需要 2 张卡片")
                    )
                } else if finished {
                    resultView
                } else if !questions.isEmpty {
                    quizView
                } else {
                    ProgressView("生成题目…")
                }
            }
            .navigationTitle("选择题模式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("退出") { dismiss() }
                }
            }
            .onAppear { buildQuestions() }
        }
    }

    // ── 答题界面 ────────────────────────────────────
    private var quizView: some View {
        let q = questions[current]
        return VStack(spacing: 0) {
            // 进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 4)
                    Rectangle().fill(Color.indigo)
                        .frame(width: geo.size.width * CGFloat(current + 1) / CGFloat(questions.count),
                               height: 4)
                        .animation(.easeInOut, value: current)
                }
            }
            .frame(height: 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 题号 + 问题
                    VStack(alignment: .leading, spacing: 8) {
                        Text("第 \(current + 1) 题 / 共 \(questions.count) 题")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(q.question)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // 选项
                    VStack(spacing: 12) {
                        ForEach(q.options.indices, id: \.self) { idx in
                            OptionButton(
                                label: optionLabel(idx),
                                text: q.options[idx],
                                state: optionState(q: q, idx: idx)
                            ) {
                                if !showAnswer { choose(q: q, idx: idx) }
                            }
                        }
                    }

                    // 解析（回答后显示）
                    if showAnswer {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(selected == q.correctIndex ? "回答正确 ✓" : "回答错误 ✗",
                                  systemImage: selected == q.correctIndex
                                    ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(selected == q.correctIndex ? .green : .red)
                                .fontWeight(.semibold)
                            Text("正确答案：\(q.options[q.correctIndex])")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background((selected == q.correctIndex ? Color.green : Color.red).opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button(action: next) {
                            Text(current < questions.count - 1 ? "下一题 →" : "查看结果")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.indigo)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding()
            }
        }
    }

    // ── 结果页 ──────────────────────────────────────
    private var resultView: some View {
        VStack(spacing: 32) {
            Spacer()
            // 得分圆环
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: Double(correctCount) / Double(questions.count))
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text("\(correctCount)/\(questions.count)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("正确")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 140, height: 140)

            VStack(spacing: 8) {
                Text(resultTitle)
                    .font(.title2.bold())
                Text("正确率 \(Int(Double(correctCount) / Double(questions.count) * 100))%")
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                Button("再来一次") {
                    buildQuestions()
                    current = 0; correctCount = 0
                    selected = nil; showAnswer = false; finished = false
                }
                .buttonStyle(.bordered)
                .tint(.indigo)

                Button("退出") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
            }
            Spacer()
        }
    }

    // ── 逻辑 ────────────────────────────────────────
    private func buildQuestions() {
        guard cards.count >= 2 else { return }
        questions = cards.shuffled().prefix(min(cards.count, 10)).map { card in
            var opts = [card.answer]
            let others = cards.filter { $0.id != card.id }.shuffled()
            for o in others.prefix(3) { opts.append(o.answer) }
            opts.shuffle()
            return QuizQuestion(
                question: card.question,
                options: opts,
                correctIndex: opts.firstIndex(of: card.answer) ?? 0
            )
        }
    }

    private func choose(q: QuizQuestion, idx: Int) {
        selected = idx
        showAnswer = true
        if idx == q.correctIndex { correctCount += 1 }
    }

    private func next() {
        if current < questions.count - 1 {
            current += 1; selected = nil; showAnswer = false
        } else {
            finished = true
        }
    }

    private func optionState(q: QuizQuestion, idx: Int) -> OptionState {
        guard showAnswer else { return selected == idx ? .selected : .normal }
        if idx == q.correctIndex { return .correct }
        if idx == selected { return .wrong }
        return .normal
    }

    private func optionLabel(_ idx: Int) -> String { ["A", "B", "C", "D"][idx] }

    private var scoreColor: Color {
        let pct = Double(correctCount) / Double(questions.count)
        return pct >= 0.8 ? .green : pct >= 0.6 ? .orange : .red
    }

    private var resultTitle: String {
        let pct = Double(correctCount) / Double(questions.count)
        return pct == 1 ? "完美！全部正确 🎉" :
               pct >= 0.8 ? "非常棒！继续保持 💪" :
               pct >= 0.6 ? "不错，还需加强 📚" : "需要多复习哦 😅"
    }
}

// MARK: - 选项按钮
enum OptionState { case normal, selected, correct, wrong }

struct OptionButton: View {
    let label: String
    let text: String
    let state: OptionState
    let action: () -> Void

    private var bg: Color {
        switch state {
        case .normal:   return Color(.systemGray6)
        case .selected: return Color.indigo.opacity(0.15)
        case .correct:  return Color.green.opacity(0.15)
        case .wrong:    return Color.red.opacity(0.15)
        }
    }
    private var border: Color {
        switch state {
        case .normal:   return .clear
        case .selected: return .indigo
        case .correct:  return .green
        case .wrong:    return .red
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Text(label)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(border == .clear ? Color.secondary.opacity(0.4) : border)
                    .clipShape(Circle())
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                if state == .correct { Image(systemName: "checkmark").foregroundColor(.green) }
                if state == .wrong   { Image(systemName: "xmark").foregroundColor(.red) }
            }
            .padding(14)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 数据模型
struct QuizQuestion {
    let question: String
    let options: [String]
    let correctIndex: Int
}
