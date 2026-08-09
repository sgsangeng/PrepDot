import Foundation

// MARK: - API 响应包装
struct APIResult<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T?
}

// MARK: - 卡组
struct Deck: Decodable, Identifiable, Hashable {
    let id: Int
    let parentId: Int?
    let depth: Int
    let title: String
    let type: String
    let category: String
    let description: String?
    let cardCount: Int
    let reviewedCount: Int
    let avgMemoryScore: Int
    let createdAt: String
}

// MARK: - 闪卡
struct Flashcard: Decodable, Identifiable, Hashable {
    let id: Int
    let deckId: Int
    let question: String
    let answer: String
    let cardType: String      // "qa" / "choice" / "blank"
    let options: String?      // 选择题选项 JSON 数组字符串
    let category: String
    let memoryScore: Int
    let reviewCount: Int
    let nextReviewAt: String?

    /// 解析 options JSON → [String]
    var parsedOptions: [String] {
        guard let raw = options,
              let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return arr
    }
}

// MARK: - 今日计划
struct TodayPlan: Decodable {
    let planId: Int
    let planDate: String
    let totalCount: Int
    let completedCount: Int
    let estimatedMinutes: Int
    let cards: [Flashcard]
}

// MARK: - 新建卡组请求
struct CreateDeckRequest: Encodable {
    let title: String
    let category: String
    let description: String
    let type: String = "自建"
}

// MARK: - 复习打分请求
struct ReviewRequest: Encodable {
    let cardId: Int
    let rating: String  // again / hard / good / easy
}

// MARK: - 用户认证
struct AuthResponse: Decodable {
    let token: String
    let userId: Int
    let username: String
    let nickname: String
    let avatarColor: String
    let studyTarget: Int
}

// MARK: - 学习统计
struct UserStats: Decodable {
    let streakDays: Int
    let todayReviewed: Int
    let totalReviewed: Int
    let totalDecks: Int
    let totalCards: Int
    let avgMemoryScore: Int
    let weeklyData: [WeeklyItem]
    let memoryDistribution: MemoryDistribution
}

struct WeeklyItem: Decodable, Identifiable {
    var id: String { day }
    let day: String    // "2024-06-01"
    let count: Int
}

struct MemoryDistribution: Decodable {
    let low: Int
    let mid: Int
    let high: Int
}

// MARK: - 知识图谱
struct KnowledgeGraphData: Decodable {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
}
struct GraphNode: Decodable, Identifiable {
    let id: String
    let label: String
    let deckId: Int
    let deckTitle: String
    let isCore: Bool
    let memoryScore: Int    // 记忆度 0-100，用于节点颜色
    let reviewCount: Int    // 复习次数，用于节点大小
}
struct GraphEdge: Decodable {
    let source: String
    let target: String
    let label: String
}

// MARK: - AI 生成预览（本地解析 AI 返回的 JSON）
struct AIPreviewDeck: Codable {
    let title: String
    let category: String
    let description: String
    var children: [AIPreviewChild]
}

struct AIPreviewChild: Codable, Identifiable {
    var id: UUID = UUID()
    let title: String
    var cards: [AIPreviewCard]

    enum CodingKeys: String, CodingKey {
        case title, cards
    }
}

struct AIPreviewCard: Codable, Identifiable {
    var id: UUID = UUID()
    let question: String
    let answer: String

    enum CodingKeys: String, CodingKey {
        case question, answer
    }
}
