import SwiftUI
import Charts

private struct ReviewTrendPoint: Codable, Identifiable {
    var id: String { date }
    let date: String
    let total, again, hard, good, easy: Int
}

private struct WeakCardPoint: Codable, Identifiable {
    var id: Int { cardId }
    let cardId: Int
    let question: String
    let memoryScore: Int
}

private struct LearningCoachMessage: Identifiable, Codable {
    enum Role: String, Codable { case user, assistant }

    let id = UUID()
    let role: Role
    let text: String
    var toolNote: String?
    var trend: [ReviewTrendPoint] = []
    var weakCards: [WeakCardPoint] = []
}

private struct LearningCoachSession: Identifiable, Codable {
    let id: UUID
    var title: String
    var updatedAt: Date
    var messages: [LearningCoachMessage]
}

struct LearningCoachView: View {
    @State private var messages: [LearningCoachMessage] = []
    @State private var input = ""
    @State private var thinking = false
    @State private var progressText = ""
    @State private var sessions: [LearningCoachSession] = []
    @State private var currentSessionId = UUID()
    @State private var showSessions = false

    private let quickQuestions = [
        "分析我最近掌握得最差的知识点",
        "看看我最近两周的复习趋势",
        "哪些卡组很久没有复习了？",
        "根据我的薄弱点生成 5 张补强卡片"
    ]

    private let toolNames = [
        "get_weak_cards": "薄弱卡片诊断",
        "get_review_trend": "复习趋势统计",
        "get_neglected_decks": "冷落卡组检查",
        "generate_supplement_cards": "补强卡片生成与质检"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                safetyBanner
                Divider()

                if messages.isEmpty {
                    intro
                } else {
                    messageList
                }

                inputBar
            }
            .navigationTitle("AI 学习教练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSessions = true } label: { Image(systemName: "clock.arrow.circlepath") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newSession() } label: { Image(systemName: "square.and.pencil") }
                }
            }
            .sheet(isPresented: $showSessions) { sessionList }
            .onAppear { loadSessions() }
        }
    }

    private var sessionList: some View {
        NavigationStack {
            List {
                ForEach(sessions.sorted { $0.updatedAt > $1.updatedAt }) { session in
                    Button {
                        saveCurrentSession()
                        currentSessionId = session.id
                        messages = session.messages
                        showSessions = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title).foregroundStyle(.primary).lineLimit(1)
                            Text(session.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteSessions)
            }
            .navigationTitle("历史会话")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { showSessions = false } }
                ToolbarItem(placement: .topBarTrailing) { Button("新建") { newSession(); showSessions = false } }
            }
        }
    }

    private var safetyBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "shield.checkered")
                .foregroundStyle(.indigo)
            Text("教练会读取你的学习数据进行诊断；生成的补强卡片仅供预览，不会自动新增、修改或删除卡片。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.indigo.opacity(0.06))
    }

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("基于真实复习数据给建议")
                        .font(.title3.weight(.semibold))
                    Text("你可以让教练查找薄弱卡片、分析复习趋势、检查长期未复习的卡组，或生成经过质检的补强卡片预览。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(quickQuestions, id: \.self) { question in
                    Button {
                        send(question)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.indigo)
                            Text(question)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(.indigo)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(thinking)
                }
            }
            .padding(16)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if thinking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(progressText.isEmpty ? "正在读取学习数据并分析…" : progressText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 14)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func messageBubble(_ message: LearningCoachMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 44) }
            VStack(alignment: .leading, spacing: 6) {
                Text(markdown(message.text))
                    .font(.body)
                    .textSelection(.enabled)
                if !message.trend.isEmpty { trendChart(message.trend) }
                if !message.weakCards.isEmpty { weakCardsChart(message.weakCards) }
                if let note = message.toolNote {
                    Label(note, systemImage: "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                message.role == .user ? Color.indigo : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .foregroundStyle(message.role == .user ? Color.white : Color.primary)
            if message.role == .assistant { Spacer(minLength: 44) }
        }
        .padding(.horizontal, 14)
    }

    private func markdown(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source,
            options: .init(interpretedSyntax: .full))) ?? AttributedString(source)
    }

    private func trendChart(_ points: [ReviewTrendPoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("近期复习量").font(.caption.weight(.semibold))
            Chart(points) { point in
                BarMark(x: .value("日期", String(point.date.suffix(5))),
                        y: .value("复习数", point.total))
                    .foregroundStyle(.indigo.gradient)
            }
            .frame(height: 150)
        }
        .padding(.top, 6)
    }

    private func weakCardsChart(_ points: [WeakCardPoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("薄弱卡片记忆度").font(.caption.weight(.semibold))
            Chart(Array(points.prefix(8))) { point in
                BarMark(x: .value("记忆度", point.memoryScore),
                        y: .value("卡片", String(point.question.prefix(10))))
                    .foregroundStyle(by: .value("类型", "记忆度"))
            }
            .chartXScale(domain: 0...100)
            .frame(height: CGFloat(min(points.count, 8) * 30 + 30))
        }
        .padding(.top, 6)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("问问最近学得怎么样…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .submitLabel(.send)
                .onSubmit { send(input) }

            Button {
                send(input)
            } label: {
                Image(systemName: thinking ? "hourglass" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(thinking ? Color.secondary : Color.indigo)
            }
            .disabled(thinking || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }

        input = ""
        messages.append(LearningCoachMessage(role: .user, text: text))
        saveCurrentSession(title: text)
        thinking = true
        progressText = "正在连接学习教练…"

        Task {
            do {
                for try await event in APIService.shared.streamLearningCoach(text) {
                    await MainActor.run {
                        switch event {
                        case .progress(let status):
                            progressText = localizedProgress(status)
                        case .result(let run):
                            let reply = run.output?.isEmpty == false
                                ? run.output!
                                : "教练没有返回有效建议（状态：\(run.status)）。"
                            messages.append(LearningCoachMessage(
                                role: .assistant,
                                text: reply,
                                toolNote: toolSummary(run),
                                trend: decodeTool(run, name: "get_review_trend"),
                                weakCards: decodeTool(run, name: "get_weak_cards")
                            ))
                            saveCurrentSession()
                            thinking = false
                        }
                    }
                }
            } catch {
                // 云端后端尚未发布 SSE 接口时，自动回退到原有 JSON 接口。
                do {
                    let run = try await APIService.shared.askLearningCoach(text)
                    await MainActor.run {
                        let reply = run.output?.isEmpty == false
                            ? run.output!
                            : "教练没有返回有效建议（状态：\(run.status)）。"
                        messages.append(LearningCoachMessage(
                            role: .assistant,
                            text: reply,
                            toolNote: toolSummary(run),
                            trend: decodeTool(run, name: "get_review_trend"),
                            weakCards: decodeTool(run, name: "get_weak_cards")
                        ))
                        saveCurrentSession()
                        thinking = false
                    }
                } catch {
                    await MainActor.run {
                        messages.append(LearningCoachMessage(
                            role: .assistant,
                            text: "分析失败：\(friendlyError(error))",
                            toolNote: nil
                        ))
                        saveCurrentSession()
                        thinking = false
                    }
                }
            }
        }
    }

    private static let sessionsKey = "learning_coach_sessions_v1"

    private func loadSessions() {
        guard sessions.isEmpty else { return }
        if let data = UserDefaults.standard.data(forKey: Self.sessionsKey),
           let saved = try? JSONDecoder().decode([LearningCoachSession].self, from: data),
           let first = saved.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            sessions = saved; currentSessionId = first.id; messages = first.messages
        } else {
            let session = LearningCoachSession(id: currentSessionId, title: "新会话", updatedAt: Date(), messages: [])
            sessions = [session]; persistSessions()
        }
    }

    private func newSession() {
        saveCurrentSession()
        currentSessionId = UUID(); messages = []
        sessions.append(.init(id: currentSessionId, title: "新会话", updatedAt: Date(), messages: []))
        persistSessions()
    }

    private func saveCurrentSession(title: String? = nil) {
        guard let index = sessions.firstIndex(where: { $0.id == currentSessionId }) else { return }
        sessions[index].messages = messages
        sessions[index].updatedAt = Date()
        if sessions[index].title == "新会话", let title { sessions[index].title = String(title.prefix(24)) }
        persistSessions()
    }

    private func deleteSessions(at offsets: IndexSet) {
        let ordered = sessions.sorted { $0.updatedAt > $1.updatedAt }
        let ids = offsets.map { ordered[$0].id }
        sessions.removeAll { ids.contains($0.id) }
        if sessions.isEmpty { newSession() }
        else if ids.contains(currentSessionId), let first = sessions.max(by: { $0.updatedAt < $1.updatedAt }) {
            currentSessionId = first.id; messages = first.messages
        }
        persistSessions()
    }

    private func persistSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.sessionsKey)
        }
    }

    private func friendlyError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet: return "网络未连接，请检查网络后重试。"
            case .timedOut: return "请求超时，请稍后重试。"
            case .userAuthenticationRequired: return "登录已失效，请重新登录。"
            default: break
            }
        }
        return "服务暂时不可用，请稍后重试。"
    }

    private func localizedProgress(_ raw: String) -> String {
        toolNames.reduce(raw) { text, pair in text.replacingOccurrences(of: pair.key, with: pair.value) }
    }

    private func decodeTool<T: Decodable>(_ run: AgentRun, name: String) -> [T] {
        guard let json = run.steps.last(where: { $0.toolName == name })?.toolResult,
              let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    private func toolSummary(_ run: AgentRun) -> String? {
        let tools = run.steps
            .filter { $0.stepType == "TOOL" }
            .compactMap { $0.toolName }
            .map { toolNames[$0] ?? $0 }
        return tools.isEmpty ? nil : "本次调用：\(tools.joined(separator: "、"))"
    }
}

#Preview {
    LearningCoachView()
}
