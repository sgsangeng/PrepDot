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
    let dueCount: Int
    let avgMemoryScore: Int
    let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id, parentId, depth, title, type, category, description
        case cardCount, reviewedCount, dueCount, avgMemoryScore, createdAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        parentId = try values.decodeIfPresent(Int.self, forKey: .parentId)
        depth = try values.decode(Int.self, forKey: .depth)
        title = try values.decode(String.self, forKey: .title)
        type = try values.decode(String.self, forKey: .type)
        category = try values.decode(String.self, forKey: .category)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        cardCount = try values.decode(Int.self, forKey: .cardCount)
        reviewedCount = try values.decode(Int.self, forKey: .reviewedCount)
        dueCount = try values.decodeIfPresent(Int.self, forKey: .dueCount) ?? 0
        avgMemoryScore = try values.decode(Int.self, forKey: .avgMemoryScore)
        createdAt = try values.decode(String.self, forKey: .createdAt)
    }
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

    /// FSRS 难度 1-10，尚未复习为 nil
    let difficulty: Double?
    /// FSRS 稳定性（天），尚未复习为 nil
    let stability: Double?

    /// 复习笔记（用户自加，不影响原始内容），无笔记为 nil/空
    let note: String?

    /// 解析 options JSON → [String]
    var parsedOptions: [String] {
        guard let raw = options,
              let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return arr
    }

    /// 兼容历史数据中的中文类型值，界面和新接口统一使用英文机器值。
    var normalizedCardType: String {
        switch cardType.lowercased() {
        case "choice", "选择", "选择题": return "choice"
        case "blank", "填空", "填空题": return "blank"
        default: return "qa"
        }
    }
}

extension String {
    /// 精选卡包常用分号连接编号项；展示时分行，但不修改数据库原文。
    var cardDisplayText: String {
        var result = self
        for marker in ["②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"] {
            result = result.replacingOccurrences(of: "； \(marker)", with: "；\n\(marker)")
            result = result.replacingOccurrences(of: "；\(marker)", with: "；\n\(marker)")
            result = result.replacingOccurrences(of: "; \(marker)", with: ";\n\(marker)")
        }
        return result
    }
}

// MARK: - 今日计划
struct TodayPlan: Decodable {
    let planId: Int
    let planDate: String
    let totalCount: Int
    let completedCount: Int
    let estimatedMinutes: Int
    var cards: [Flashcard]
    let deckProgress: [DeckReviewProgress]

    private enum CodingKeys: String, CodingKey {
        case planId, planDate, totalCount, completedCount, estimatedMinutes, cards, deckProgress
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        planId = try values.decode(Int.self, forKey: .planId)
        planDate = try values.decode(String.self, forKey: .planDate)
        totalCount = try values.decode(Int.self, forKey: .totalCount)
        completedCount = try values.decode(Int.self, forKey: .completedCount)
        estimatedMinutes = try values.decode(Int.self, forKey: .estimatedMinutes)
        cards = try values.decode([Flashcard].self, forKey: .cards)
        deckProgress = try values.decodeIfPresent([DeckReviewProgress].self, forKey: .deckProgress) ?? []
    }
}

struct DeckReviewProgress: Decodable, Identifiable {
    let deckId: Int
    let deckTitle: String
    let totalCount: Int
    let completedCount: Int

    var id: Int { deckId }
    var pendingCount: Int { max(0, totalCount - completedCount) }
    var isCompleted: Bool { totalCount > 0 && completedCount >= totalCount }
    var progress: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }
}

// MARK: - 新建卡组请求
struct CreateDeckRequest: Encodable {
    let title: String
    let category: String
    let description: String
    let parentId: Int?
    let type: String = "自建"
}

// MARK: - 复习打分请求
struct ReviewRequest: Encodable {
    let cardId: Int
    let rating: String  // again / hard / good / easy
}

// MARK: - 今日复习小结
struct ReviewSummary: Decodable {
    let totalCount: Int
    let decks: [ReviewSummaryDeck]
}

struct ReviewSummaryDeck: Decodable, Identifiable {
    var id: Int { deckId }
    let deckId: Int
    let deckTitle: String
    let count: Int
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

// MARK: - AI 学习教练（Agent）

struct CoachRequest: Encodable {
    let message: String
    let mode: String
}

struct NoteRequest: Encodable {
    let note: String
}

/// Agent 一次运行的完整记录（含可回放的每一步轨迹）
struct AgentRun: Decodable {
    let runId: Int
    let status: String          // RUNNING / SUCCEEDED / FAILED
    let output: String?         // 教练最终回答
    let stepCount: Int
    let steps: [AgentStep]
}

struct AgentStep: Decodable, Identifiable {
    var id: Int { stepNo }
    let stepNo: Int
    let stepType: String        // MODEL / TOOL
    let modelContent: String?
    let toolName: String?
    let toolArguments: String?
    let toolResult: String?
    let durationMs: Int?
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
