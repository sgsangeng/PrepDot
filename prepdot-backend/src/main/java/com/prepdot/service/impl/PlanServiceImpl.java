package com.prepdot.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.prepdot.common.BusinessException;
import com.prepdot.algorithm.FsrsScheduler;
import com.prepdot.algorithm.FsrsState;
import com.prepdot.dto.request.ReviewRequest;
import com.prepdot.dto.response.ReviewSummaryVO;
import com.prepdot.dto.response.TodayPlanVO;
import com.prepdot.entity.*;
import com.prepdot.mapper.*;
import com.prepdot.service.PlanService;
import com.prepdot.service.FsrsMemoryService;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class PlanServiceImpl implements PlanService {

    private static final int DEFAULT_DAILY_TARGET = 20;
    private static final Set<String> VALID_RATINGS = Set.of("again", "hard", "good", "easy");

    private final DailyPlanMapper     planMapper;
    private final DailyPlanItemMapper planItemMapper;
    private final FlashcardMapper     flashcardMapper;
    private final ReviewRecordMapper  reviewRecordMapper;
    private final DeckMapper          deckMapper;
    private final UserMapper          userMapper;
    private final FsrsScheduler       fsrsScheduler;
    private final FsrsMemoryService   fsrsMemoryService;

    /** 每日计划上限取用户设置的学习目标，未设置时回退默认值 */
    private int dailyTarget(Long userId) {
        if (userId == null) return DEFAULT_DAILY_TARGET;
        User user = userMapper.selectById(userId);
        if (user == null || user.getStudyTarget() == null || user.getStudyTarget() <= 0) {
            return DEFAULT_DAILY_TARGET;
        }
        return user.getStudyTarget();
    }

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
        } else {
            // 计划已存在时，把当天新导入/新建的到期卡片补进来，避免计划被首次生成的结果固化
            replenishPlan(plan, userId);
        }

        List<DailyPlanItem> items = planItemMapper.selectList(
                new LambdaQueryWrapper<DailyPlanItem>()
                        .eq(DailyPlanItem::getPlanId, plan.getId())
        );

        List<Long> cardIds = items.stream().map(DailyPlanItem::getCardId).collect(Collectors.toList());
        List<Flashcard> allCards = cardIds.isEmpty() ? List.of() : flashcardMapper.selectBatchIds(cardIds);
        Map<Long, Flashcard> cardsById = allCards.stream()
                .collect(Collectors.toMap(Flashcard::getId, Function.identity()));
        List<Flashcard> cards = items.stream()
                .filter(item -> "pending".equals(item.getStatus()))
                .map(item -> cardsById.get(item.getCardId()))
                .filter(java.util.Objects::nonNull)
                .toList();
        LocalDateTime now = LocalDateTime.now();
        cards.forEach(card -> card.setMemoryScore(fsrsMemoryService.currentScore(card, now)));

        List<Long> deckIds = allCards.stream().map(Flashcard::getDeckId).distinct().toList();
        Map<Long, String> deckTitles = deckIds.isEmpty() ? Map.of() : deckMapper.selectBatchIds(deckIds)
                .stream()
                .collect(Collectors.toMap(Deck::getId, Deck::getTitle));
        Map<Long, TodayPlanVO.DeckProgress> progressByDeck = new LinkedHashMap<>();
        for (DailyPlanItem item : items) {
            Flashcard card = cardsById.get(item.getCardId());
            if (card == null) continue;
            TodayPlanVO.DeckProgress progress = progressByDeck.computeIfAbsent(card.getDeckId(), deckId -> {
                TodayPlanVO.DeckProgress value = new TodayPlanVO.DeckProgress();
                value.setDeckId(deckId);
                value.setDeckTitle(deckTitles.getOrDefault(deckId, "未命名卡组"));
                value.setTotalCount(0);
                value.setCompletedCount(0);
                return value;
            });
            progress.setTotalCount(progress.getTotalCount() + 1);
            if ("done".equals(item.getStatus())) {
                progress.setCompletedCount(progress.getCompletedCount() + 1);
            }
        }

        TodayPlanVO vo = new TodayPlanVO();
        vo.setPlanId(plan.getId());
        vo.setPlanDate(plan.getPlanDate());
        vo.setTotalCount(plan.getTotalCount());
        vo.setCompletedCount(plan.getCompletedCount());
        vo.setEstimatedMinutes(plan.getEstimatedMinutes());
        vo.setCards(cards);
        vo.setDeckProgress(new ArrayList<>(progressByDeck.values()));
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

        // 校验这张卡片所在卡组是否属于当前用户；公共卡组（user_id NULL）为只读目录，不可复习
        Deck deck = deckMapper.selectById(card.getDeckId());
        if (deck == null || deck.getUserId() == null || !deck.getUserId().equals(userId)) {
            throw BusinessException.forbidden("无权操作该卡片");
        }

        LocalDateTime now = LocalDateTime.now();
        int scoreBefore = fsrsMemoryService.currentScore(card, now);
        int reviewCount = card.getReviewCount()  != null ? card.getReviewCount()  : 0;
        int rating = switch (request.getRating()) {
            case "again" -> 1; case "hard" -> 2; case "good" -> 3; case "easy" -> 4;
            default -> throw BusinessException.badRequest("无效评分");
        };
        FsrsState nextState;
        if (card.getDifficulty() == null || card.getStability() == null || card.getLastReviewedAt() == null) {
            nextState = fsrsScheduler.initialState(rating);
        } else {
            double elapsedDays = fsrsMemoryService.elapsedDays(card.getLastReviewedAt(), now);
            nextState = fsrsScheduler.reviewExisting(
                    new FsrsState(card.getDifficulty(), card.getStability()), rating, elapsedDays);
        }
        int days = fsrsScheduler.nextIntervalDays(nextState.stability());

        card.setDifficulty(nextState.difficulty());
        card.setStability(nextState.stability());
        card.setReviewCount(reviewCount + 1);
        card.setLastReviewedAt(now);
        // again 属于短期重新学习步骤：立即重新进入到期队列，当日计划项回置 pending（见下方）。
        card.setNextReviewAt(rating == 1 ? now : now.plusDays(days));
        flashcardMapper.updateById(card);
        // 记忆度为展示值：复习刚结束时可召回率恒为 100，随时间由 FSRS 实时衰减
        int scoreAfter = fsrsMemoryService.currentScore(card, now);
        card.setMemoryScore(scoreAfter);

        // 写复习记录（携带 userId）
        ReviewRecord record = new ReviewRecord();
        record.setCardId(card.getId());
        record.setRating(request.getRating());
        record.setMemoryScoreBefore(scoreBefore);
        record.setMemoryScoreAfter(scoreAfter);
        record.setUserId(userId);
        reviewRecordMapper.insert(record);

        // 更新当日计划项：again 回置 pending 当日重学，其余评分标记 done
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
            );
            boolean planChanged = false;
            if (rating == 1) {
                if (item == null) {
                    DailyPlanItem relearn = new DailyPlanItem();
                    relearn.setPlanId(plan.getId());
                    relearn.setCardId(card.getId());
                    relearn.setStatus("pending");
                    try {
                        planItemMapper.insert(relearn);
                        plan.setTotalCount(plan.getTotalCount() + 1);
                        plan.setEstimatedMinutes(plan.getTotalCount() * 2);
                        planChanged = true;
                    } catch (DuplicateKeyException ignored) {
                        // 并发下已存在该项，保持现状
                    }
                } else if ("done".equals(item.getStatus())) {
                    item.setStatus("pending");
                    planItemMapper.updateById(item);
                    plan.setCompletedCount(Math.max(0, plan.getCompletedCount() - 1));
                    planChanged = true;
                }
            } else if (item != null && "pending".equals(item.getStatus())) {
                item.setStatus("done");
                planItemMapper.updateById(item);
                plan.setCompletedCount(plan.getCompletedCount() + 1);
                planChanged = true;
            }
            if (planChanged) {
                planMapper.updateById(plan);
            }
        }

        return card;
    }

    @Override
    public ReviewSummaryVO getTodaySummary(Long userId) {
        List<Map<String, Object>> rows = reviewRecordMapper.todayReviewByDeck(userId);

        List<ReviewSummaryVO.DeckCount> decks = rows.stream().map(m -> {
            ReviewSummaryVO.DeckCount d = new ReviewSummaryVO.DeckCount();
            d.setDeckId(((Number) m.get("deckId")).longValue());
            d.setDeckTitle((String) m.get("deckTitle"));
            d.setCount(((Number) m.get("reviewCount")).intValue());
            return d;
        }).collect(Collectors.toList());

        ReviewSummaryVO vo = new ReviewSummaryVO();
        vo.setTotalCount(decks.stream().mapToInt(ReviewSummaryVO.DeckCount::getCount).sum());
        vo.setDecks(decks);
        return vo;
    }

    private DailyPlan generatePlan(LocalDate date, Long userId) {
        List<Flashcard> dueCards = flashcardMapper.selectDueCards(dailyTarget(userId), userId);

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

    /**
     * 给已存在的当日计划补入新到期的卡片：只加入那些尚未出现在计划里的卡片，
     * 已 done / 已 pending 的项保持不变；总量不超过用户每日目标，避免大批导入后计划爆量。
     */
    private void replenishPlan(DailyPlan plan, Long userId) {
        List<DailyPlanItem> existingItems = planItemMapper.selectList(
                new LambdaQueryWrapper<DailyPlanItem>()
                        .eq(DailyPlanItem::getPlanId, plan.getId()));
        Set<Long> existingCardIds = existingItems.stream()
                .map(DailyPlanItem::getCardId)
                .collect(Collectors.toSet());

        int capacity = dailyTarget(userId) - existingItems.size();
        if (capacity <= 0) {
            return;
        }

        List<Flashcard> dueCards = flashcardMapper.selectAllDueCards(userId);

        int added = 0;
        for (Flashcard card : dueCards) {
            if (added >= capacity) {
                break;
            }
            if (existingCardIds.contains(card.getId())) {
                continue;
            }
            DailyPlanItem item = new DailyPlanItem();
            item.setPlanId(plan.getId());
            item.setCardId(card.getId());
            item.setStatus("pending");
            try {
                planItemMapper.insert(item);
                added++;
            } catch (DuplicateKeyException ignored) {
                // 并发补题已插入该卡片，唯一约束兜底，跳过
            }
        }

        if (added > 0) {
            plan.setTotalCount(plan.getTotalCount() + added);
            plan.setEstimatedMinutes(plan.getTotalCount() * 2);
            planMapper.updateById(plan);
        }
    }
}
