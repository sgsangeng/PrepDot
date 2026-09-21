import Foundation

class APIService {
    static let shared = APIService()

    // 默认连接云端，保证真机、模拟器和 Release 包都可直接演示。
    // 本地调试可在 Xcode Scheme 中设置 PREPDOT_API_BASE_URL=http://localhost:8080/api。
    #if DEBUG
    private let base = ProcessInfo.processInfo.environment["PREPDOT_API_BASE_URL"]
        ?? "https://api.adeer.site/prepdot/api"
    #else
    private let base = "https://api.adeer.site/prepdot/api"
    #endif

    /// 本地后端不可达时尽快失败，避免界面长期停留在加载状态。
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration)
    }()

    /// 登录后的 JWT token（由 AuthManager 注入）
    var token: String? = UserDefaults.standard.string(forKey: "jwt_token")

    /// 是否正在刷新中（防止并发重复刷新）
    private var isRefreshing = false

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func url(_ path: String) -> URL {
        URL(string: base + path)!
    }

    // MARK: - Token 续期

    /// 解码 JWT payload 获取过期时间（不需要 secret，只读 base64）
    private func tokenExpiryDate(_ token: String) -> Date? {
        // JWT 格式: header.payload.signature，payload 是第二段
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // JWT 使用 Base64URL；转换后补齐标准 Base64 padding
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// 检查 token 是否即将过期（7 天有效期剩余不足一半）
    private func isTokenExpiringSoon() -> Bool {
        guard let t = token,
              let expiry = tokenExpiryDate(t)
        else { return true }
        let refreshThreshold: TimeInterval = 3.5 * 24 * 3600
        return expiry.timeIntervalSinceNow < refreshThreshold
    }

    /// 调用后端刷新接口获取新 token
    @discardableResult
    func refreshToken() async throws -> AuthResponse {
        guard !isRefreshing else { throw URLError(.cannotLoadFromNetwork) }
        isRefreshing = true
        defer { isRefreshing = false }
        var req = URLRequest(url: url("/auth/refresh"))
        req.httpMethod = "POST"
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: req)
        // 刷新接口本身也可能返回 401（token 已经过期太久）
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            AuthManager.shared.logout()
            throw URLError(.userAuthenticationRequired)
        }
        let result = try decoder.decode(APIResult<AuthResponse>.self, from: data)
        guard let value = result.data else {
            throw URLError(.badServerResponse)
        }
        // 自动更新本地存储和内存中的 token
        AuthManager.shared.login(with: value)
        return value
    }

    /// 如果 token 快过期了就自动续期（静默）
    @discardableResult
    func tryAutoRefreshIfNeeded() async throws -> Bool {
        guard !isRefreshing, isTokenExpiringSoon() else { return false }
        do {
            _ = try await refreshToken()
            print("[APIService] Token 已自动续期")
            return true
        } catch {
            print("[APIService] 自动续期失败: \(error)")
            return false
        }
    }

    // MARK: - 通用 GET
    private func get<T: Decodable>(_ path: String) async throws -> T {
        var req = URLRequest(url: url(path))
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: req)

        // 处理 401：token 过期或无效 → 强制登出
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            AuthManager.shared.logout()
            throw URLError(.userAuthenticationRequired)
        }

        let result = try decoder.decode(APIResult<T>.self, from: data)
        guard let value = result.data else {
            throw APIServiceError.server(result.message)
        }

        // 请求成功后检查是否需要自动续期
        _ = try? await tryAutoRefreshIfNeeded()

        return value
    }

    // MARK: - 用户认证
    func register(username: String, password: String, nickname: String) async throws -> AuthResponse {
        struct Body: Encodable { let username, password, nickname: String }
        return try await send(method: "POST", path: "/auth/register",
                              body: Body(username: username, password: password, nickname: nickname))
    }

    func login(username: String, password: String) async throws -> AuthResponse {
        struct Body: Encodable { let username, password: String }
        return try await send(method: "POST", path: "/auth/login",
                              body: Body(username: username, password: password))
    }

    func fetchStats() async throws -> UserStats {
        try await get("/auth/stats")
    }

    /// 永久删除当前账号及其关联学习数据。
    func deleteAccount(password: String) async throws {
        struct Body: Encodable { let password: String }
        struct Response: Decodable { let code: Int; let message: String }

        var req = URLRequest(url: url("/auth/account"))
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONEncoder().encode(Body(password: password))

        let (data, urlResponse) = try await session.data(for: req)
        let result = try decoder.decode(Response.self, from: data)
        guard let http = urlResponse as? HTTPURLResponse,
              (200..<300).contains(http.statusCode), result.code == 200 else {
            throw APIServiceError.server(result.message)
        }
    }

    // MARK: - 通用 POST/PUT
    private func send<Body: Encodable, T: Decodable>(
        method: String, path: String, body: Body
    ) async throws -> T {
        var req = URLRequest(url: url(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: req)

        // 处理 401：token 过期或无效 → 强制登出
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            AuthManager.shared.logout()
            throw URLError(.userAuthenticationRequired)
        }

        let result = try decoder.decode(APIResult<T>.self, from: data)
        guard let value = result.data else {
            throw URLError(.badServerResponse)
        }

        // 请求成功后检查是否需要自动续期
        _ = try? await tryAutoRefreshIfNeeded()

        return value
    }

    // MARK: - 卡组
    func fetchDecks() async throws -> [Deck] {
        try await get("/decks")
    }

    func fetchChildDecks(parentId: Int) async throws -> [Deck] {
        let all: [Deck] = try await get("/decks")
        return all.filter { $0.parentId == parentId }
    }

    // MARK: - 카片 CRUD
    func createCard(deckId: Int, question: String, answer: String,
                    cardType: String = "qa", options: String? = nil) async throws -> Flashcard {
        struct Body: Encodable {
            let deckId: Int; let question: String; let answer: String
            let cardType: String; let options: String?
        }
        return try await send(method: "POST", path: "/cards",
                              body: Body(deckId: deckId, question: question, answer: answer,
                                        cardType: cardType, options: options))
    }

    func updateCard(id: Int, question: String, answer: String,
                    cardType: String = "qa", options: String? = nil) async throws -> Flashcard {
        struct Body: Encodable {
            let question: String; let answer: String
            let cardType: String; let options: String?
        }
        return try await send(method: "PUT", path: "/cards/\(id)",
                              body: Body(question: question, answer: answer,
                                        cardType: cardType, options: options))
    }

    /// 更新卡片复习笔记（空字符串 = 清除笔记），不影响原始内容
    func updateCardNote(id: Int, note: String) async throws -> Flashcard {
        try await send(method: "PUT", path: "/cards/\(id)/note",
                       body: NoteRequest(note: note))
    }

    func deleteCard(id: Int) async throws {
        var req = URLRequest(url: url("/cards/\(id)"))
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.httpMethod = "DELETE"
        _ = try await session.data(for: req)
    }

    func deleteCards(ids: [Int]) async throws {
        let query = ids.map { "ids=\($0)" }.joined(separator: "&")
        var req = URLRequest(url: URL(string: base + "/cards/batch?\(query)")!)
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.httpMethod = "DELETE"
        _ = try await session.data(for: req)
    }

    func createDeck(_ req: CreateDeckRequest) async throws -> Deck {
        try await send(method: "POST", path: "/decks", body: req)
    }

    func updateDeck(id: Int, title: String, category: String, description: String) async throws -> Deck {
        struct Body: Encodable { let title: String; let category: String; let description: String }
        return try await send(method: "PUT", path: "/decks/\(id)",
                              body: Body(title: title, category: category, description: description))
    }

    func moveDeck(id: Int, parentId: Int?) async throws -> Deck {
        struct Body: Encodable { let parentId: Int? }
        return try await send(method: "PUT", path: "/decks/\(id)/parent",
                              body: Body(parentId: parentId))
    }

    func deleteDeck(id: Int) async throws {
        var req = URLRequest(url: url("/decks/\(id)"))
        req.httpMethod = "DELETE"
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        _ = try await session.data(for: req)
    }

    func fetchCards(deckId: Int) async throws -> [Flashcard] {
        try await get("/decks/\(deckId)/cards")
    }

    /// 获取卡组及其所有子卡组内的卡片（用于掌握度散点图）
    func fetchCardsDeep(deckId: Int) async throws -> [Flashcard] {
        try await get("/decks/\(deckId)/cards?deep=true")
    }

    // MARK: - AI 学习教练（Agent）
    /// 当前卡片快速答疑：不运行学习数据诊断工具，只请求模型一次。
    func askCoach(_ message: String) async throws -> AgentRun {
        try await send(method: "POST", path: "/agent/coach",
                       body: CoachRequest(message: message, mode: "CARD_QA"))
    }

    /// 完整学习教练：允许模型调用薄弱卡片、复习趋势、冷落卡组和补强卡片工具。
    func askLearningCoach(_ message: String) async throws -> AgentRun {
        try await send(method: "POST", path: "/agent/coach",
                       body: CoachRequest(message: message, mode: "LEARNING_COACH"))
    }

    enum CoachStreamEvent {
        case progress(String)
        case result(AgentRun)
    }

    /// SSE：逐步返回 Agent 执行进度，最后返回完整、可校验的运行结果。
    func streamLearningCoach(_ message: String) -> AsyncThrowingStream<CoachStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var req = URLRequest(url: url("/agent/coach/stream"))
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
                    req.httpBody = try JSONEncoder().encode(CoachRequest(message: message, mode: "LEARNING_COACH"))
                    let (bytes, response) = try await session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw URLError(.badServerResponse)
                    }
                    var event = "message"
                    var data: [String] = []
                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            data.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        } else if line.isEmpty, !data.isEmpty {
                            let payload = data.joined(separator: "\n")
                            if event == "progress" {
                                continuation.yield(.progress(payload))
                            } else if event == "result", let raw = payload.data(using: .utf8) {
                                continuation.yield(.result(try decoder.decode(AgentRun.self, from: raw)))
                            } else if event == "error" {
                                throw APIServiceError.server(payload)
                            }
                            event = "message"; data.removeAll(keepingCapacity: true)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - 今日计划
    func fetchTodayPlan() async throws -> TodayPlan {
        try await get("/plan/today")
    }

    func fetchTodaySummary() async throws -> ReviewSummary {
        try await get("/plan/summary")
    }

    func submitReview(_ req: ReviewRequest) async throws -> Flashcard {
        try await send(method: "POST", path: "/plan/review", body: req)
    }

    // MARK: - AI 生成
    /// 上传文件 → 返回 AI 生成的层级卡组 JSON 字符串（预览用，不入库）
    func generateDeckFromFile(
        fileData: Data,
        fileName: String,
        deckTitle: String,
        customKey: String = "",
        cardCount: Int = 10,
        detailHint: String = "答案简洁，不超过50字"
    ) async throws -> String {
        var req = URLRequest(url: url("/ai/generate"))
        req.httpMethod = "POST"
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // 文本字段 helper
        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        addField("deckTitle", deckTitle)
        addField("customKey", customKey)
        addField("cardCount", "\(cardCount)")
        addField("detailHint", detailHint)

        // 文件字段
        let mimeType = mimeType(for: fileName)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, _) = try await session.data(for: req)
        let result = try decoder.decode(APIResult<String>.self, from: data)
        guard let value = result.data else {
            throw URLError(.badServerResponse)
        }
        return value
    }

    /// 将层级 JSON 入库
    func importDeckJson(_ json: String) async throws -> Deck {
        var req = URLRequest(url: url("/ai/import"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.httpBody = json.data(using: .utf8)
        let (data, _) = try await session.data(for: req)
        let result = try decoder.decode(APIResult<Deck>.self, from: data)
        guard let value = result.data else {
            throw URLError(.badServerResponse)
        }
        return value
    }

    private func mimeType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":  return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "txt":  return "text/plain"
        case "md":   return "text/markdown"
        default:     return "application/octet-stream"
        }
    }

    // MARK: - 社区卡包
    func getCommunityPacks() async throws -> [CommunityPack] {
        try await get("/community/packs")
    }

    func getCommunityPackDetail(id: Int) async throws -> CommunityPackDetail {
        try await get("/community/packs/\(id)")
    }

    @discardableResult
    func importCommunityPack(id: Int) async throws -> Deck {
        struct Empty: Encodable {}
        return try await send(method: "POST", path: "/community/packs/\(id)/import", body: Empty())
    }
}

enum APIServiceError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        }
    }
}
