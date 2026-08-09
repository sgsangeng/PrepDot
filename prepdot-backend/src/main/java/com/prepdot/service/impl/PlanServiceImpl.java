package com.prepdot.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.prepdot.common.BusinessException;
import com.prepdot.dto.request.ReviewRequest;
import com.prepdot.dto.response.TodayPlanVO;
import com.prepdot.entity.*;
import com.prepdot.mapper.*;
import com.prepdot.service.PlanService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class PlanServiceImpl implements PlanService {

    private static final int DAILY_TARGET = 20;
    private static final Set<String> VALID_RATINGS = Set.of("again", "hard", "good", "easy");

    private final DailyPlanMapper     planMapper;
    private final DailyPlanItemMapper planItemMapper;
    private final FlashcardMapper     flashcardMapper;
    private final ReviewRecordMapper  reviewRecordMapper;
    private final DeckMapper          deckMapper;

    @Override
    @Transactional
    public TodayPlanVO getTodayPlan(Long userId) {
        LocalDate today = LocalDate.now();

        // 查当天当前用户的计划
        DailyPlan plan = planMapper.selectOne(
                new LambdaQueryWrapper<DailyPlan>()
                        .eq(DailyPlan::getPlanDate, today)
                        .eq(userId != null, DailyPlan::getUserId, userId)
        );

        if (plan == null) {
            plan = generatePlan(today, userId);
        }

        List<DailyPlanItem> items = planItemMapper.selectList(
                new LambdaQueryWrapper<DailyPlanItem>()
                        .eq(DailyPlanItem::getPlanId, plan.getId())
                        .eq(DailyPlanItem::getStatus, "pending")
        );

        List<Long> cardIds = items.stream().map(DailyPlanItem::getCardId).collect(Collectors.toList());
        List<Flashcard> cards = cardIds.isEmpty() ? List.of() : flashcardMapper.selectBatchIds(cardIds);

        TodayPlanVO vo = new TodayPlanVO();
        vo.setPlanId(plan.getId());
        vo.setPlanDate(plan.getPlanDate());
        vo.setTotalCount(plan.getTotalCount());
        vo.setCompletedCount(plan.getCompletedCount());
        vo.setEstimatedMinutes(plan.getEstimatedMinutes());
        vo.setCards(cards);
        return vo;
    }

    @Override
    @Transactional
    public Flashcard submitReview(ReviewRequest request, Long userId) {
        // 校验 rating 合法性
        if (!VALID_RATINGS.contains(request.getRating())) {
            throw BusinessException.badRequest("无效的评分值：" + request.getRating() + "，只允许 again/hard/good/easy");
        }

        Flashcard card = flashcardMapper.selectById(request.getCardId());
        if (card == null) throw BusinessException.notFound("卡片不存在: " + request.getCardId());

        // 校验这张卡片所在卡组是否属于当前用户，防止越权修改他人卡片的记忆分数
        Deck deck = deckMapper.selectById(card.getDeckId());
        if (deck != null && deck.getUserId() != null && !deck.getUserId().equals(userId)) {
            throw BusinessException.forbidden("无权操作该卡片");
        }

        int scoreBefore = card.getMemoryScore() != null ? card.getMemoryScore() : 35;
        int reviewCount = card.getReviewCount()  != null ? card.getReviewCount()  : 0;

        int delta, days;
        switch (request.getRating()) {
            case "again" -> { delta = -18; days = 0; }
            case "hard"  -> { delta =   3; days = 1; }
            case "good"  -> { delta =  12; days = reviewCount < 2 ? 2 : 4; }
            case "easy"  -> { delta =  20; days = reviewCount < 2 ? 5 : 10; }
            default      -> throw new RuntimeException("无效评分"); // 不会到达，上面已校验
        }

        int scoreAfter = Math.max(0, Math.min(100, scoreBefore + delta));

        card.setMemoryScore(scoreAfter);
        card.setReviewCount(reviewCount + 1);
        card.setLastReviewedAt(LocalDateTime.now());
        card.setNextReviewAt(days == 0 ? LocalDateTime.now() : LocalDateTime.now().plusDays(days));
        flashcardMapper.updateById(card);

        // 写复习记录（携带 userId）
        ReviewRecord record = new ReviewRecord();
        record.setCardId(card.getId());
        record.setRating(request.getRating());
        record.setMemoryScoreBefore(scoreBefore);
        record.setMemoryScoreAfter(scoreAfter);
        record.setUserId(userId);
        reviewRecordMapper.insert(record);

        // 更新当日计划项
        LocalDate today = LocalDate.now();
        DailyPlan plan = planMapper.selectOne(
                new LambdaQueryWrapper<DailyPlan>()
                        .eq(DailyPlan::getPlanDate, today)
                        .eq(userId != null, DailyPlan::getUserId, userId)
        );
        if (plan != null) {
            DailyPlanItem item = planItemMapper.selectOne(
                    new LambdaQueryWrapper<DailyPlanItem>()
                            .eq(DailyPlanItem::getPlanId, plan.getId())
                            .eq(DailyPlanItem::getCardId, card.getId())
                            .eq(DailyPlanItem::getStatus, "pending")
            );
            if (item != null) {
                item.setStatus("done");
                planItemMapper.updateById(item);
                plan.setCompletedCount(plan.getCompletedCount() + 1);
                planMapper.updateById(plan);
            }
        }

        return card;
    }

    private DailyPlan generatePlan(LocalDate date, Long userId) {
        List<Flashcard> dueCards = flashcardMapper.selectDueCards(DAILY_TARGET, userId);

        DailyPlan plan = new DailyPlan();
        plan.setPlanDate(date);
        plan.setUserId(userId);
        plan.setTotalCount(dueCards.size());
        plan.setCompletedCount(0);
        plan.setEstimatedMinutes(dueCards.size() * 2);
        planMapper.insert(plan);

        for (Flashcard card : dueCards) {
            DailyPlanItem item = new DailyPlanItem();
            item.setPlanId(plan.getId());
            item.setCardId(card.getId());
            item.setStatus("pending");
            planItemMapper.insert(item);
        }

        return plan;
    }
}
