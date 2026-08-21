package com.prepdot.service;

import com.prepdot.algorithm.FsrsScheduler;
import com.prepdot.dto.request.ReviewRequest;
import com.prepdot.entity.Deck;
import com.prepdot.entity.Flashcard;
import com.prepdot.mapper.*;
import com.prepdot.service.impl.PlanServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class PlanServiceImplFsrsTest {
    private final DailyPlanMapper planMapper = mock(DailyPlanMapper.class);
    private final DailyPlanItemMapper itemMapper = mock(DailyPlanItemMapper.class);
    private final FlashcardMapper cardMapper = mock(FlashcardMapper.class);
    private final ReviewRecordMapper recordMapper = mock(ReviewRecordMapper.class);
    private final DeckMapper deckMapper = mock(DeckMapper.class);
    private final FsrsScheduler scheduler = new FsrsScheduler();
    private final FsrsMemoryService memoryService = new FsrsMemoryService(scheduler);
    private PlanServiceImpl service;

    @BeforeEach
    void setUp() {
        service = new PlanServiceImpl(planMapper, itemMapper, cardMapper, recordMapper,
                deckMapper, scheduler, memoryService);
    }

    @Test
    void firstGoodReview_initializesFsrsStateAndSchedulesByStability() {
        Flashcard card = newCard();
        when(cardMapper.selectById(10L)).thenReturn(card);
        when(deckMapper.selectById(20L)).thenReturn(ownedDeck());
        ReviewRequest request = review("good");

        Flashcard result = service.submitReview(request, 7L);

        assertEquals(5.1618, result.getDifficulty(), 0.0001);
        assertEquals(3.7145, result.getStability(), 0.0001);
        assertEquals(1, result.getReviewCount());
        assertEquals(100, result.getMemoryScore());
        long scheduledDays = java.time.Duration.between(result.getLastReviewedAt(), result.getNextReviewAt()).toDays();
        assertEquals(4, scheduledDays);
        verify(cardMapper).updateById(card);
        verify(recordMapper).insert(org.mockito.ArgumentMatchers.<com.prepdot.entity.ReviewRecord>argThat(
                record -> record.getMemoryScoreBefore() == 35 && record.getMemoryScoreAfter() == 100));
    }

    @Test
    void existingAgainReview_updatesForgetStateAndIsImmediatelyDue() {
        Flashcard card = newCard();
        card.setDifficulty(5.1618);
        card.setStability(3.7145);
        card.setReviewCount(1);
        card.setLastReviewedAt(LocalDateTime.now().minusDays(4));
        when(cardMapper.selectById(10L)).thenReturn(card);
        when(deckMapper.selectById(20L)).thenReturn(ownedDeck());

        Flashcard result = service.submitReview(review("again"), 7L);

        assertEquals(2, result.getReviewCount());
        assertTrue(result.getStability() > 0);
        assertTrue(result.getStability() < 3.7145);
        assertEquals(result.getLastReviewedAt(), result.getNextReviewAt());
    }

    private Flashcard newCard() {
        Flashcard card = new Flashcard();
        card.setId(10L);
        card.setDeckId(20L);
        card.setMemoryScore(35);
        card.setReviewCount(0);
        return card;
    }

    private Deck ownedDeck() {
        Deck deck = new Deck();
        deck.setId(20L);
        deck.setUserId(7L);
        return deck;
    }

    private ReviewRequest review(String rating) {
        ReviewRequest request = new ReviewRequest();
        request.setCardId(10L);
        request.setRating(rating);
        return request;
    }
}
