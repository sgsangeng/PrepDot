package com.prepdot.service;

import com.prepdot.algorithm.FsrsScheduler;
import com.prepdot.entity.Flashcard;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;

class FsrsMemoryServiceTest {
    private final FsrsMemoryService service = new FsrsMemoryService(new FsrsScheduler());

    @Test
    void currentScore_afterOneStabilityPeriod_isNinety() {
        LocalDateTime now = LocalDateTime.of(2026, 8, 17, 12, 0);
        Flashcard card = new Flashcard();
        card.setDifficulty(5.0);
        card.setStability(10.0);
        card.setLastReviewedAt(now.minusDays(10));
        card.setMemoryScore(100);

        assertEquals(90, service.currentScore(card, now));
    }

    @Test
    void currentScore_beforeFirstReview_usesInitialScore() {
        Flashcard card = new Flashcard();
        card.setMemoryScore(35);
        assertEquals(35, service.currentScore(card, LocalDateTime.now()));
    }
}
