package com.prepdot.service;

import com.baomidou.mybatisplus.core.MybatisConfiguration;
import com.baomidou.mybatisplus.core.metadata.TableInfoHelper;
import com.prepdot.algorithm.FsrsScheduler;
import com.prepdot.dto.request.ReviewRequest;
import com.prepdot.dto.response.TodayPlanVO;
import com.prepdot.entity.DailyPlan;
import com.prepdot.entity.DailyPlanItem;
import com.prepdot.entity.Deck;
import com.prepdot.entity.Flashcard;
import com.prepdot.mapper.*;
import com.prepdot.service.impl.PlanServiceImpl;
import org.apache.ibatis.builder.MapperBuilderAssistant;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

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

    @Test
    void todayPlanContainsProgressForEveryDeckIncludingCompletedItems() {
        TableInfoHelper.initTableInfo(
                new MapperBuilderAssistant(new MybatisConfiguration(), "test"), DailyPlan.class);
        TableInfoHelper.initTableInfo(
                new MapperBuilderAssistant(new MybatisConfiguration(), "test"), DailyPlanItem.class);
        FsrsMemoryService mockedMemoryService = mock(FsrsMemoryService.class);
        PlanServiceImpl planService = new PlanServiceImpl(
                planMapper, itemMapper, cardMapper, recordMapper,
                deckMapper, scheduler, mockedMemoryService);

        DailyPlan plan = new DailyPlan();
        plan.setId(100L);
        plan.setUserId(7L);
        plan.setPlanDate(LocalDate.now());
        plan.setTotalCount(3);
        plan.setCompletedCount(1);
        plan.setEstimatedMinutes(6);
        when(planMapper.selectOne(any())).thenReturn(plan);

        DailyPlanItem done = planItem(1L, "done");
        DailyPlanItem pendingA = planItem(2L, "pending");
        DailyPlanItem pendingB = planItem(3L, "pending");
        when(itemMapper.selectList(any())).thenReturn(List.of(done, pendingA, pendingB));
        when(cardMapper.selectAllDueCards(7L)).thenReturn(List.of());

        Flashcard card1 = planCard(1L, 10L);
        Flashcard card2 = planCard(2L, 10L);
        Flashcard card3 = planCard(3L, 20L);
        when(cardMapper.selectBatchIds(any())).thenReturn(List.of(card1, card2, card3));
        Deck deckA = deck(10L, "Redis");
        Deck deckB = deck(20L, "MySQL");
        when(deckMapper.selectBatchIds(any())).thenReturn(List.of(deckA, deckB));
        when(mockedMemoryService.currentScore(any(), any())).thenReturn(35);

        TodayPlanVO result = planService.getTodayPlan(7L);

        assertEquals(2, result.getCards().size());
        assertEquals(2, result.getDeckProgress().size());
        assertEquals(2, result.getDeckProgress().get(0).getTotalCount());
        assertEquals(1, result.getDeckProgress().get(0).getCompletedCount());
        assertEquals(1, result.getDeckProgress().get(1).getTotalCount());
        assertEquals(0, result.getDeckProgress().get(1).getCompletedCount());
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

    private DailyPlanItem planItem(Long cardId, String status) {
        DailyPlanItem item = new DailyPlanItem();
        item.setPlanId(100L);
        item.setCardId(cardId);
        item.setStatus(status);
        return item;
    }

    private Flashcard planCard(Long id, Long deckId) {
        Flashcard card = new Flashcard();
        card.setId(id);
        card.setDeckId(deckId);
        card.setMemoryScore(35);
        card.setReviewCount(0);
        return card;
    }

    private Deck deck(Long id, String title) {
        Deck deck = new Deck();
        deck.setId(id);
        deck.setTitle(title);
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
