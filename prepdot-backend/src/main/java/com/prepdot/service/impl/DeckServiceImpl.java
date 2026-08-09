package com.prepdot.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.prepdot.dto.request.CardRequest;
import com.prepdot.dto.request.DeckRequest;
import com.prepdot.dto.response.DeckVO;
import com.prepdot.entity.Deck;
import com.prepdot.entity.Flashcard;
import com.prepdot.mapper.DeckMapper;
import com.prepdot.mapper.FlashcardMapper;
import com.prepdot.service.DeckService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class DeckServiceImpl implements DeckService {

    private final DeckMapper deckMapper;
    private final FlashcardMapper flashcardMapper;

    @Override
    public List<DeckVO> listAll(Long userId) {
        LambdaQueryWrapper<Deck> qw = new LambdaQueryWrapper<>();
        if (userId != null) {
            qw.eq(Deck::getUserId, userId);
        }
        List<Deck> decks = deckMapper.selectList(qw);
        return decks.stream().map(this::toVO).collect(Collectors.toList());
    }

    @Override
    @Transactional
    public DeckVO create(DeckRequest request, Long userId) {
        // 新建卡组
        Deck deck = new Deck();
        deck.setTitle(request.getTitle());
        deck.setType(request.getType() != null ? request.getType() : "导入卡包");
        deck.setCategory(request.getCategory() != null ? request.getCategory() : "综合");
        deck.setDescription(request.getDescription());
        deck.setParentId(null);
        deck.setDepth(0);
        deck.setUserId(userId);
        deckMapper.insert(deck);

        // 批量导入卡片（如果携带了）
        if (request.getCards() != null && !request.getCards().isEmpty()) {
            for (CardRequest cr : request.getCards()) {
                Flashcard card = new Flashcard();
                card.setDeckId(deck.getId());
                card.setQuestion(cr.getQuestion());
                card.setAnswer(cr.getAnswer());
                card.setCategory(cr.getCategory() != null ? cr.getCategory() : deck.getCategory());
                card.setMemoryScore(35);
                card.setReviewCount(0);
                card.setNextReviewAt(LocalDateTime.now());
                flashcardMapper.insert(card);
            }
        }

        return toVO(deck);
    }

    /**
     * 根据 AI 生成的层级 JSON 批量创建卡组 + 卡片
     * JSON 格式：{ "title", "category", "description", "children": [ { "title", "cards": [...] } ] }
     */
    @Override
    @Transactional
    public DeckVO createHierarchical(JsonNode root, Long userId) {
        String title    = root.path("title").asText("AI 生成卡组");
        String category = root.path("category").asText("综合");
        String desc     = root.path("description").asText("");

        // 1. 创建根卡组
        Deck rootDeck = new Deck();
        rootDeck.setTitle(title);
        rootDeck.setType("AI生成");
        rootDeck.setCategory(category);
        rootDeck.setDescription(desc);
        rootDeck.setParentId(null);
        rootDeck.setDepth(0);
        rootDeck.setUserId(userId);
        deckMapper.insert(rootDeck);

        // 2. 根级卡片（如果有）
        insertCards(rootDeck, root.path("cards"));

        // 3. 子卡组（depth=1）
        JsonNode children = root.path("children");
        if (children.isArray()) {
            for (JsonNode child : children) {
                Deck childDeck = new Deck();
                childDeck.setTitle(child.path("title").asText("子卡组"));
                childDeck.setType("AI生成");
                childDeck.setCategory(category);
                childDeck.setDescription("");
                childDeck.setParentId(rootDeck.getId());
                childDeck.setDepth(1);
                childDeck.setUserId(userId);
                deckMapper.insert(childDeck);
                insertCards(childDeck, child.path("cards"));

                // 孙卡组（depth=2，最多一层）
                JsonNode grandchildren = child.path("children");
                if (grandchildren.isArray()) {
                    for (JsonNode gc : grandchildren) {
                        Deck gcDeck = new Deck();
                        gcDeck.setTitle(gc.path("title").asText("子卡组"));
                        gcDeck.setType("AI生成");
                        gcDeck.setCategory(category);
                        gcDeck.setDescription("");
                        gcDeck.setParentId(childDeck.getId());
                        gcDeck.setDepth(2);
                        gcDeck.setUserId(userId);
                        deckMapper.insert(gcDeck);
                        insertCards(gcDeck, gc.path("cards"));
                    }
                }
            }
        }

        return toVO(rootDeck);
    }

    private void insertCards(Deck deck, JsonNode cardsNode) {
        if (!cardsNode.isArray()) return;
        for (JsonNode c : cardsNode) {
            String q = c.path("question").asText("");
            String a = c.path("answer").asText("");
            if (q.isBlank() || a.isBlank()) continue;
            Flashcard card = new Flashcard();
            card.setDeckId(deck.getId());
            card.setQuestion(q);
            card.setAnswer(a);
            card.setCategory(deck.getCategory());
            card.setMemoryScore(35);
            card.setReviewCount(0);
            card.setNextReviewAt(LocalDateTime.now());
            flashcardMapper.insert(card);
        }
    }

    @Override
    @Transactional
    public DeckVO update(Long id, DeckRequest request) {
        Deck deck = deckMapper.selectById(id);
        if (deck == null) throw new IllegalArgumentException("卡组不存在：" + id);
        if (request.getTitle() != null && !request.getTitle().isBlank()) {
            deck.setTitle(request.getTitle().trim());
        }
        if (request.getCategory() != null) {
            deck.setCategory(request.getCategory().trim());
        }
        if (request.getDescription() != null) {
            deck.setDescription(request.getDescription().trim());
        }
        deckMapper.updateById(deck);
        return toVO(deck);
    }

    @Override
    @Transactional
    public void delete(Long id) {
        // 先删卡片（ON DELETE CASCADE 也会处理，双保险）
        flashcardMapper.delete(
                new LambdaQueryWrapper<Flashcard>().eq(Flashcard::getDeckId, id)
        );
        deckMapper.deleteById(id);
    }

    @Override
    public List<Flashcard> listCards(Long deckId) {
        return flashcardMapper.selectList(
                new LambdaQueryWrapper<Flashcard>()
                        .eq(Flashcard::getDeckId, deckId)
                        .orderByAsc(Flashcard::getCreatedAt)
        );
    }

    // ---- 私有辅助 ----

    private DeckVO toVO(Deck deck) {
        List<Flashcard> cards = flashcardMapper.selectList(
                new LambdaQueryWrapper<Flashcard>().eq(Flashcard::getDeckId, deck.getId())
        );

        DeckVO vo = new DeckVO();
        vo.setId(deck.getId());
        vo.setParentId(deck.getParentId());
        vo.setDepth(deck.getDepth() != null ? deck.getDepth() : 0);
        vo.setTitle(deck.getTitle());
        vo.setType(deck.getType());
        vo.setCategory(deck.getCategory());
        vo.setDescription(deck.getDescription());
        vo.setCreatedAt(deck.getCreatedAt());
        vo.setCardCount(cards.size());
        vo.setReviewedCount((int) cards.stream()
                .filter(c -> c.getReviewCount() != null && c.getReviewCount() > 0)
                .count());
        vo.setAvgMemoryScore(cards.isEmpty() ? 0 :
                (int) cards.stream()
                        .mapToInt(c -> c.getMemoryScore() != null ? c.getMemoryScore() : 35)
                        .average()
                        .orElse(0));
        return vo;
    }
}
