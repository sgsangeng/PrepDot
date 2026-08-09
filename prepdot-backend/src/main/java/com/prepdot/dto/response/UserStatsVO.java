package com.prepdot.dto.response;

import lombok.Data;
import java.util.List;
import java.util.Map;

@Data
public class UserStatsVO {
    private int streakDays;          // 连续打卡天数
    private int todayReviewed;       // 今日已复习
    private int totalReviewed;       // 历史总复习次数
    private int totalDecks;          // 总卡组数
    private int totalCards;          // 总卡片数
    private int avgMemoryScore;      // 全局平均记忆度

    // 近 7 天每日复习数（用于柱状图）
    // 格式：[{ "day": "06-01", "count": 12 }, ...]
    private List<Map<String, Object>> weeklyData;

    // 记忆度分布：{ "low": 10, "mid": 30, "high": 20 }
    private Map<String, Object> memoryDistribution;
}
