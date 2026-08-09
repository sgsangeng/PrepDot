package com.prepdot.dto.response;

import lombok.Data;

import java.time.LocalDateTime;

@Data
public class DeckVO {

    private Long id;
    private Long parentId;
    private Integer depth;
    private String title;
    private String type;
    private String category;
    private String description;

    /** 卡组内总卡片数 */
    private Integer cardCount;

    /** 已复习过至少一次的卡片数 */
    private Integer reviewedCount;

    /** 平均记忆度 0-100 */
    private Integer avgMemoryScore;

    private LocalDateTime createdAt;
}
