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
import com.prepdot.service.FsrsMemoryService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

@Service
@RequiredArgsConstructor
public class DeckServiceImpl implements DeckService {

    private final DeckMapper deckMapper;
    private final FlashcardMapper flashcardMapper;
    private final FsrsMemoryService fsrsMemoryService;

    @Override
    public List<DeckVO> listAll(Long userId) {
        LambdaQueryWrapper<Deck> qw = new LambdaQueryWrapper<>();
        if (userId != null) {
            qw.eq(Deck::getUserId, userId);
        }
        List<Deck> decks = deckMapper.selectList(qw);
        if (decks.isEmpty()) {
            return List.of();
        }

        List<Long> deckIds = decks.stream().map(Deck::getId).toList();
        List<Flashcard> cards = flashcardMapper.selectList(
                new LambdaQueryWrapper<Flashcard>().in(Flashcard::getDeckId, deckIds)
        );

        Map<Long, List<Long>> childrenByParent = new HashMap<>();
        for (Deck deck : decks) {
            if (deck.getParentId() != null) {
                childrenByParent.computeIfAbsent(deck.getParentId(), ignored -> new ArrayList<>())
                        .add(deck.getId());
            }
        }

        Map<Long, List<Flashcard>> cardsByDeck = new HashMap<>();
        for (Flashcard card : cards) {
            cardsByDeck.computeIfAbsent(card.getDeckId(), ignored -> new ArrayList<>()).add(card);
        }

        LocalDateTime now = LocalDateTime.now();
        Map<Long, List<Flashcard>> subtreeCache = new HashMap<>();
        List<DeckVO> result = new ArrayList<>(decks.size());
        for (Deck deck : decks) {
            List<Flashcard> subtreeCards = collectSubtreeCards(
                    deck.getId(), childrenByParent, cardsByDeck, subtreeCache, new HashSet<>());
            result.add(toVO(deck, subtreeCards, now));
        }
        return result;
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
        Deck parent = findOwnedParent(request.getParentId(), userId);
        deck.setParentId(parent == null ? null : parent.getId());
        deck.setDepth(parent == null ? 0 : parent.getDepth() + 1);
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
    public DeckVO move(Long id, Long parentId, Long userId) {
        List<Deck> ownedDecks = deckMapper.selectList(
                new LambdaQueryWrapper<Deck>().eq(Deck::getUserId, userId)
        );
        Map<Long, Deck> byId = new HashMap<>();
        Map<Long, List<Deck>> childrenByParent = new HashMap<>();
        for (Deck item : ownedDecks) {
            byId.put(item.getId(), item);
            if (item.getParentId() != null) {
                childrenByParent.computeIfAbsent(item.getParentId(), ignored -> new ArrayList<>()).add(item);
            }
        }

        Deck deck = byId.get(id);
        if (deck == null) {
            throw new IllegalArgumentException("卡组不存在或无权操作");
        }
        Deck parent = parentId == null ? null : byId.get(parentId);
        if (parentId != null && parent == null) {
            throw new IllegalArgumentException("父节点不存在或不属于当前用户");
        }

        Map<Long, Integer> relativeDepths = collectSubtreeDepths(id, childrenByParent);
        if (parentId != null && relativeDepths.containsKey(parentId)) {
            throw new IllegalArgumentException("不能把节点移动到自己或自己的子节点下");
        }

        int targetDepth = parent == null ? 0 : parent.getDepth() + 1;
        int maxRelativeDepth = relativeDepths.values().stream().mapToInt(Integer::intValue).max().orElse(0);
        if (targetDepth + maxRelativeDepth > 2) {
            throw new IllegalArgumentException("知识树最多支持三级");
        }

        deck.setParentId(parentId);
        for (Map.Entry<Long, Integer> entry : relativeDepths.entrySet()) {
            Deck item = byId.get(entry.getKey());
            item.setDepth(targetDepth + entry.getValue());
            deckMapper.updateById(item);
        }
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
        List<Flashcard> cards = flashcardMapper.selectList(
                new LambdaQueryWrapper<Flashcard>()
                        .eq(Flashcard::getDeckId, deckId)
                        .orderByAsc(Flashcard::getCreatedAt)
        );
        LocalDateTime now = LocalDateTime.now();
        cards.forEach(card -> card.setMemoryScore(fsrsMemoryService.currentScore(card, now)));
        return cards;
    }

    @Override
    public List<Flashcard> listCardsDeep(Long deckId, Long userId) {
        // 一次查询当前用户可访问的卡组，内存里建 parentId → children 映射，再 BFS 收集子树，
        // 避免逐层查库的 N+1。卡组层级最多 3 层，内存遍历代价可忽略。
        LambdaQueryWrapper<Deck> deckQuery = new LambdaQueryWrapper<>();
        if (userId != null) {
            deckQuery.and(q -> q.eq(Deck::getUserId, userId).or().isNull(Deck::getUserId));
        } else {
            deckQuery.isNull(Deck::getUserId);
        }
        List<Deck> allDecks = deckMapper.selectList(deckQuery);
        Map<Long, List<Long>> childrenMap = new HashMap<>();
        for (Deck d : allDecks) {
            if (d.getParentId() != null) {
                childrenMap.computeIfAbsent(d.getParentId(), k -> new ArrayList<>()).add(d.getId());
            }
        }

        List<Long> deckIds = new ArrayList<>();
        Deque<Long> queue = new ArrayDeque<>();
        queue.add(deckId);
        while (!queue.isEmpty()) {
            Long cur = queue.poll();
            deckIds.add(cur);
            queue.addAll(childrenMap.getOrDefault(cur, List.of()));
        }

        if (deckIds.isEmpty()) {
            return List.of();
        }
        List<Flashcard> cards = flashcardMapper.selectList(
                new LambdaQueryWrapper<Flashcard>()
                        .in(Flashcard::getDeckId, deckIds)
                        .orderByAsc(Flashcard::getCreatedAt)
        );
        LocalDateTime now = LocalDateTime.now();
        cards.forEach(card -> card.setMemoryScore(fsrsMemoryService.currentScore(card, now)));
        return cards;
    }

    // ---- 私有辅助 ----

    private DeckVO toVO(Deck deck) {
        List<Flashcard> cards = flashcardMapper.selectList(
                new LambdaQueryWrapper<Flashcard>().eq(Flashcard::getDeckId, deck.getId())
        );
        return toVO(deck, cards, LocalDateTime.now());
    }

    private Deck findOwnedParent(Long parentId, Long userId) {
        if (parentId == null) {
            return null;
        }
        Deck parent = deckMapper.selectById(parentId);
        if (parent == null || !Objects.equals(parent.getUserId(), userId)) {
            throw new IllegalArgumentException("父节点不存在或不属于当前用户");
        }
        if (parent.getDepth() >= 2) {
            throw new IllegalArgumentException("知识树最多支持三级");
        }
        return parent;
    }

    private Map<Long, Integer> collectSubtreeDepths(
            Long rootId, Map<Long, List<Deck>> childrenByParent) {
        Map<Long, Integer> result = new HashMap<>();
        Deque<Long> ids = new ArrayDeque<>();
        Deque<Integer> depths = new ArrayDeque<>();
        ids.add(rootId);
        depths.add(0);
        while (!ids.isEmpty()) {
            Long currentId = ids.removeFirst();
            int relativeDepth = depths.removeFirst();
            if (result.putIfAbsent(currentId, relativeDepth) != null) {
                continue;
            }
            for (Deck child : childrenByParent.getOrDefault(currentId, List.of())) {
                ids.addLast(child.getId());
                depths.addLast(relativeDepth + 1);
            }
        }
        return result;
    }

    /**
     * 汇总节点及其所有后代卡片。缓存让同一子树只计算一次；visiting 防御历史脏数据形成环。
     */
    private List<Flashcard> collectSubtreeCards(
            Long deckId,
            Map<Long, List<Long>> childrenByParent,
            Map<Long, List<Flashcard>> cardsByDeck,
            Map<Long, List<Flashcard>> cache,
            Set<Long> visiting) {
        if (cache.containsKey(deckId)) {
            return cache.get(deckId);
        }
        if (!visiting.add(deckId)) {
            return List.of();
        }

        List<Flashcard> result = new ArrayList<>(cardsByDeck.getOrDefault(deckId, List.of()));
        for (Long childId : childrenByParent.getOrDefault(deckId, List.of())) {
            result.addAll(collectSubtreeCards(
                    childId, childrenByParent, cardsByDeck, cache, visiting));
        }
        visiting.remove(deckId);
        List<Flashcard> immutableResult = List.copyOf(result);
        cache.put(deckId, immutableResult);
        return immutableResult;
    }

    private DeckVO toVO(Deck deck, List<Flashcard> cards, LocalDateTime now) {

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
        vo.setDueCount((int) cards.stream()
                .filter(c -> c.getNextReviewAt() != null && !c.getNextReviewAt().isAfter(now))
                .count());
        vo.setAvgMemoryScore(cards.isEmpty() ? 0 :
                (int) cards.stream()
                        .mapToInt(c -> c.getReviewCount() != null && c.getReviewCount() > 0
                                ? fsrsMemoryService.currentScore(c, now)
                                : 0)
                        .average()
                        .orElse(0));
        return vo;
    }
}
