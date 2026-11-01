package com.prepdot.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.prepdot.common.BusinessException;
import com.prepdot.dto.request.CardRequest;
import com.prepdot.entity.Deck;
import com.prepdot.entity.Flashcard;
import com.prepdot.mapper.DeckMapper;
import com.prepdot.mapper.FlashcardMapper;
import com.prepdot.service.CardService;
import com.prepdot.service.FsrsMemoryService;
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
    private final FsrsMemoryService fsrsMemoryService;

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
        card.setReviewCount(0);
        card.setNextReviewAt(LocalDateTime.now());
        flashcardMapper.insert(card);
        card.setMemoryScore(fsrsMemoryService.currentScore(card, LocalDateTime.now()));
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
        card.setMemoryScore(fsrsMemoryService.currentScore(card, LocalDateTime.now()));
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
    public Flashcard updateNote(Long id, String note, Long userId) {
        Flashcard card = flashcardMapper.selectById(id);
        if (card == null) throw BusinessException.notFound("卡片不存在: " + id);
        checkDeckOwner(card.getDeckId(), userId);

        // 只更新 note 一列，question/answer/options 等原始内容完全不受影响
        Flashcard patch = new Flashcard();
        patch.setId(id);
        patch.setNote(note);
        flashcardMapper.updateById(patch);

        card.setNote(note);
        card.setMemoryScore(fsrsMemoryService.currentScore(card, LocalDateTime.now()));
        return card;
    }

    @Override
    public void deleteBatch(List<Long> ids, Long userId) {
        if (ids == null || ids.isEmpty()) return;

        List<Flashcard> cards = flashcardMapper.selectBatchIds(ids);
        if (cards.isEmpty()) return;

        // 找出这批卡片各自所属的卡组，一次性查出来，避免逐张查（N+1）
        List<Long> deckIds = cards.stream().map(Flashcard::getDeckId).distinct().toList();
        List<Deck> decks = deckMapper.selectBatchIds(deckIds);

        // 只保留确实属于当前用户的卡组（公共卡组只读，不在可删范围内）
        var ownedDeckIds = decks.stream()
                .filter(d -> userId.equals(d.getUserId()))
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

    /** 校验卡组归属：公共卡组（user_id NULL）为只读目录，写操作一律拒绝 */
    private void checkDeckOwner(Long deckId, Long userId) {
        Deck deck = deckMapper.selectById(deckId);
        if (deck == null) throw BusinessException.notFound("卡组不存在: " + deckId);
        if (deck.getUserId() == null || !deck.getUserId().equals(userId)) {
            throw BusinessException.forbidden("公共卡组只读，请先导入到自己的卡组再操作");
        }
    }
}
