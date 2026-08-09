package com.prepdot.dto.response;

import com.prepdot.entity.Flashcard;
import lombok.Data;

import java.time.LocalDate;
import java.util.List;

@Data
public class TodayPlanVO {

    private Long planId;
    private LocalDate planDate;
    private Integer totalCount;
    private Integer completedCount;
    private Integer estimatedMinutes;

    /** 今日待复习卡片列表 */
    private List<Flashcard> cards;
}
