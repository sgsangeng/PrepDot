package com.prepdot.dto.response;

import lombok.Data;

import java.util.List;

/**
 * 今日复习小结：今天复习了多少张卡片、分别来自哪些卡组。
 */
@Data
public class ReviewSummaryVO {

    /** 今日复习过的不同卡片总数 */
    private int totalCount;

    /** 按卡组分组的小结 */
    private List<DeckCount> decks = new java.util.ArrayList<>();

    @Data
    public static class DeckCount {
        private Long deckId;
        private String deckTitle;
        private int count;
    }
}
