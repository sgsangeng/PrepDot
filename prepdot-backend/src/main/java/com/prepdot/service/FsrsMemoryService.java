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

    public int currentScore(Flashcard card, LocalDateTime now) {
        if (card.getDifficulty() == null || card.getStability() == null || card.getLastReviewedAt() == null) {
            return card.getMemoryScore() == null ? 35 : card.getMemoryScore();
        }
        double elapsedDays = elapsedDays(card.getLastReviewedAt(), now);
        return (int) Math.round(100 * scheduler.retrievability(card.getStability(), elapsedDays));
    }

    public double elapsedDays(LocalDateTime from, LocalDateTime to) {
        if (from == null || !to.isAfter(from)) return 0.0;
        return Duration.between(from, to).toMinutes() / 1440.0;
    }
}
