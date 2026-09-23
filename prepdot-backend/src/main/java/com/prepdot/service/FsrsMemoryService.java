package com.prepdot.service;

import com.prepdot.algorithm.FsrsScheduler;
import com.prepdot.entity.Flashcard;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.time.LocalDateTime;

@Service
@RequiredArgsConstructor
public class FsrsMemoryService {
    private final FsrsScheduler scheduler;

    /** 尚未复习的新卡没有 FSRS 状态，展示固定初始记忆度 */
    private static final int NEW_CARD_SCORE = 35;

    public int currentScore(Flashcard card, LocalDateTime now) {
        if (card.getDifficulty() == null || card.getStability() == null || card.getLastReviewedAt() == null) {
            return NEW_CARD_SCORE;
        }
        double elapsedDays = elapsedDays(card.getLastReviewedAt(), now);
        return (int) Math.round(100 * scheduler.retrievability(card.getStability(), elapsedDays));
    }

    public double elapsedDays(LocalDateTime from, LocalDateTime to) {
        if (from == null || !to.isAfter(from)) return 0.0;
        return Duration.between(from, to).toMinutes() / 1440.0;
    }
}
