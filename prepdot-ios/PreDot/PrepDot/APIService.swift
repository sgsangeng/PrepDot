import Foundation

class APIService {
    static let shared = APIService()

    // iOS 模拟器访问 Mac 本机 Spring Boot 用这个地址
    #if targetEnvironment(simulator)
    private let base = "http://localhost:8080/api"
    #else
    private let base = "http://10.44.2.238:8080/api"   // Mac 局域网 IP，真机用
    #endif

    /// 登录后的 JWT token（由 AuthManager 注入）
    var token: String? = UserDefaults.standard.string(forKey: "jwt_token")

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func url(_ path: String) -> URL {
        URL(string: base + path)!
    }

    // MARK: - 通用 GET
    private func get<T: Decodable>(_ path: String) async throws -> T {
        var req = URLRequest(url: url(path))
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, _) = try await URLSession.shared.data(for: req)
        let result = try decoder.decode(APIResult<T>.self, from: data)
        guard let value = result.data else {
            throw URLError(.badServerResponse)
        }
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

    // MARK: - 通用 POST/PUT
    private func send<Body: Encodable, T: Decodable>(
        method: String, path: String, body: Body
    ) async throws -> T {
        var req = URLRequest(url: url(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: req)
        let result = try decoder.decode(APIResult<T>.self, from: data)
        guard let value = result.data else {
            throw URLError(.badServerResponse)
        }
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

    func fetchKnowledgeGraph(customKey: String = "") async throws -> KnowledgeGraphData {
        let path = customKey.isEmpty ? "/ai/knowledge-graph" : "/ai/knowledge-graph?customKey=\(customKey)"
        return try await get(path)
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

    func deleteCard(id: Int) async throws {
        var req = URLRequest(url: url("/cards/\(id)"))
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.httpMethod = "DELETE"
        _ = try await URLSession.shared.data(for: req)
    }

    func deleteCards(ids: [Int]) async throws {
        let query = ids.map { "ids=\($0)" }.joined(separator: "&")
        var req = URLRequest(url: URL(string: base + "/cards/batch?\(query)")!)
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.httpMethod = "DELETE"
        _ = try await URLSession.shared.data(for: req)
    }

    func createDeck(_ req: CreateDeckRequest) async throws -> Deck {
        try await send(method: "POST", path: "/decks", body: req)
    }

    func updateDeck(id: Int, title: String, category: String, description: String) async throws -> Deck {
        struct Body: Encodable { let title: String; let category: String; let description: String }
        return try await send(method: "PUT", path: "/decks/\(id)",
                              body: Body(title: title, category: category, description: description))
    }

    func deleteDeck(id: Int) async throws {
        var req = URLRequest(url: url("/decks/\(id)"))
        req.httpMethod = "DELETE"
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        _ = try await URLSession.shared.data(for: req)
    }

    func fetchCards(deckId: Int) async throws -> [Flashcard] {
        try await get("/decks/\(deckId)/cards")
    }

    // MARK: - 今日计划
    func fetchTodayPlan() async throws -> TodayPlan {
        try await get("/plan/today")
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

        let (data, _) = try await URLSession.shared.data(for: req)
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
        let (data, _) = try await URLSession.shared.data(for: req)
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
