package com.prepdot.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.prepdot.common.BusinessException;
import com.prepdot.dto.request.CardRequest;
import com.prepdot.entity.Deck;
import com.prepdot.entity.Flashcard;
import com.prepdot.mapper.DeckMapper;
import com.prepdot.mapper.FlashcardMapper;
import com.prepdot.service.CardService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class CardServiceImpl implements CardService {

    private final FlashcardMapper flashcardMapper;
    private final DeckMapper      deckMapper;

    @Override
    public Flashcard create(CardRequest request, Long userId) {
        checkDeckOwner(request.getDeckId(), userId);

        Flashcard card = new Flashcard();
        card.setDeckId(request.getDeckId());
        card.setQuestion(request.getQuestion());
        card.setAnswer(request.getAnswer());
        card.setCategory(request.getCategory() != null ? request.getCategory() : "综合");
        card.setCardType(request.getCardType() != null ? request.getCardType() : "qa");
        card.setOptions(request.getOptions());
        card.setMemoryScore(35);
        card.setReviewCount(0);
        card.setNextReviewAt(LocalDateTime.now());
        flashcardMapper.insert(card);
        return card;
    }

    @Override
    public Flashcard update(Long id, CardRequest request, Long userId) {
        Flashcard card = flashcardMapper.selectById(id);
        if (card == null) throw BusinessException.notFound("卡片不存在: " + id);
        checkDeckOwner(card.getDeckId(), userId);

        if (request.getQuestion() != null) card.setQuestion(request.getQuestion());
        if (request.getAnswer()   != null) card.setAnswer(request.getAnswer());
        if (request.getCategory() != null) card.setCategory(request.getCategory());
        if (request.getCardType() != null) card.setCardType(request.getCardType());
        card.setOptions(request.getOptions());

        flashcardMapper.updateById(card);
        return card;
    }

    @Override
    public void delete(Long id, Long userId) {
        Flashcard card = flashcardMapper.selectById(id);
        if (card == null) throw BusinessException.notFound("卡片不存在: " + id);
        checkDeckOwner(card.getDeckId(), userId);
        flashcardMapper.deleteById(id);
    }

    @Override
    public void deleteBatch(List<Long> ids, Long userId) {
        if (ids == null || ids.isEmpty()) return;

        List<Flashcard> cards = flashcardMapper.selectBatchIds(ids);
        if (cards.isEmpty()) return;

        // 找出这批卡片各自所属的卡组，一次性查出来，避免逐张查（N+1）
        List<Long> deckIds = cards.stream().map(Flashcard::getDeckId).distinct().toList();
        List<Deck> decks = deckMapper.selectBatchIds(deckIds);

        // 只保留“确实属于 userId”的卡组 id 集合
        var ownedDeckIds = decks.stream()
                .filter(d -> d.getUserId() == null || d.getUserId().equals(userId))
                .map(Deck::getId)
                .collect(java.util.stream.Collectors.toSet());

        // 请求删除的卡片里，只有属于自己卡组的那部分才真正被删除
        List<Long> allowedIds = cards.stream()
                .filter(c -> ownedDeckIds.contains(c.getDeckId()))
                .map(Flashcard::getId)
                .toList();

        int skipped = ids.size() - allowedIds.size();
        if (skipped > 0) {
            log.warn("批量删除卡片：请求 {} 张，其中 {} 张不属于用户 {}，已忽略", ids.size(), skipped, userId);
        }
        if (!allowedIds.isEmpty()) {
            flashcardMapper.delete(new LambdaQueryWrapper<Flashcard>().in(Flashcard::getId, allowedIds));
        }
    }

    /** 校验卡组归属：userId==null 的卡组视为公共/历史数据，不做拦截 */
    private void checkDeckOwner(Long deckId, Long userId) {
        Deck deck = deckMapper.selectById(deckId);
        if (deck == null) throw BusinessException.notFound("卡组不存在: " + deckId);
        if (deck.getUserId() != null && !deck.getUserId().equals(userId)) {
            throw BusinessException.forbidden("无权操作该卡组下的卡片");
        }
    }
}
