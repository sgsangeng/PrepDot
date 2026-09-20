package com.prepdot.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.MybatisConfiguration;
import com.baomidou.mybatisplus.core.metadata.TableInfoHelper;
import com.prepdot.dto.request.DeckRequest;
import com.prepdot.entity.Deck;
import com.prepdot.entity.Flashcard;
import com.prepdot.mapper.DeckMapper;
import com.prepdot.mapper.FlashcardMapper;
import com.prepdot.service.impl.DeckServiceImpl;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.apache.ibatis.builder.MapperBuilderAssistant;

import java.time.LocalDateTime;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.when;

class DeckServiceImplIsolationTest {

    @Test
    void deepCardQueryRestrictsDecksToCurrentUserAndPublicData() {
        TableInfoHelper.initTableInfo(
                new MapperBuilderAssistant(new MybatisConfiguration(), "test"), Deck.class);
        DeckMapper deckMapper = mock(DeckMapper.class);
        FlashcardMapper cardMapper = mock(FlashcardMapper.class);
        FsrsMemoryService memoryService = mock(FsrsMemoryService.class);
        DeckServiceImpl service = new DeckServiceImpl(deckMapper, cardMapper, memoryService);

        Deck root = deck(10L, null);
        Deck child = deck(11L, 10L);
        when(deckMapper.selectList(any())).thenReturn(List.of(root, child));
        when(cardMapper.selectList(any())).thenReturn(List.of());

        List<Flashcard> result = service.listCardsDeep(10L, 7L);

        assertTrue(result.isEmpty());
        @SuppressWarnings("unchecked")
        ArgumentCaptor<LambdaQueryWrapper<Deck>> captor =
                ArgumentCaptor.forClass(LambdaQueryWrapper.class);
        verify(deckMapper).selectList(captor.capture());
        String sql = captor.getValue().getSqlSegment();
        assertTrue(sql.contains("user_id"));
        assertTrue(captor.getValue().getParamNameValuePairs().containsValue(7L));
    }

    @Test
    void listAllAggregatesDescendantCardsWithoutNPlusOneQueries() {
        TableInfoHelper.initTableInfo(
                new MapperBuilderAssistant(new MybatisConfiguration(), "test"), Deck.class);
        TableInfoHelper.initTableInfo(
                new MapperBuilderAssistant(new MybatisConfiguration(), "test"), Flashcard.class);
        DeckMapper deckMapper = mock(DeckMapper.class);
        FlashcardMapper cardMapper = mock(FlashcardMapper.class);
        FsrsMemoryService memoryService = mock(FsrsMemoryService.class);
        DeckServiceImpl service = new DeckServiceImpl(deckMapper, cardMapper, memoryService);

        Deck root = deck(10L, null);
        Deck child = deck(11L, 10L);
        Deck grandchild = deck(12L, 11L);
        when(deckMapper.selectList(any())).thenReturn(List.of(root, child, grandchild));

        Flashcard reviewed = card(100L, 11L, 2, LocalDateTime.now().minusDays(1));
        Flashcard newCard = card(101L, 12L, 0, LocalDateTime.now().plusDays(1));
        when(cardMapper.selectList(any())).thenReturn(List.of(reviewed, newCard));
        when(memoryService.currentScore(any(), any())).thenReturn(80);

        List<com.prepdot.dto.response.DeckVO> result = service.listAll(7L);

        assertEquals(3, result.size());
        assertEquals(2, result.get(0).getCardCount());
        assertEquals(1, result.get(0).getReviewedCount());
        assertEquals(1, result.get(0).getDueCount());
        assertEquals(40, result.get(0).getAvgMemoryScore());
        assertEquals(1, result.get(2).getCardCount());
        assertEquals(0, result.get(2).getAvgMemoryScore());
        verify(cardMapper, times(1)).selectList(any());
    }

    @Test
    void moveRejectsDescendantAsParent() {
        DeckMapper deckMapper = mock(DeckMapper.class);
        FlashcardMapper cardMapper = mock(FlashcardMapper.class);
        DeckServiceImpl service = new DeckServiceImpl(deckMapper, cardMapper, mock(FsrsMemoryService.class));
        Deck root = deck(10L, null, 0);
        Deck child = deck(11L, 10L, 1);
        Deck grandchild = deck(12L, 11L, 2);
        when(deckMapper.selectList(any())).thenReturn(List.of(root, child, grandchild));

        IllegalArgumentException error = assertThrows(
                IllegalArgumentException.class, () -> service.move(10L, 12L, 7L));

        assertTrue(error.getMessage().contains("子节点"));
        verify(deckMapper, never()).updateById(any(Deck.class));
    }

    @Test
    void moveUpdatesDepthForWholeSubtree() {
        DeckMapper deckMapper = mock(DeckMapper.class);
        FlashcardMapper cardMapper = mock(FlashcardMapper.class);
        DeckServiceImpl service = new DeckServiceImpl(deckMapper, cardMapper, mock(FsrsMemoryService.class));
        Deck root = deck(10L, null, 0);
        Deck child = deck(11L, 10L, 1);
        Deck grandchild = deck(12L, 11L, 2);
        when(deckMapper.selectList(any())).thenReturn(List.of(root, child, grandchild));
        when(cardMapper.selectList(any())).thenReturn(List.of());

        service.move(11L, null, 7L);

        assertEquals(null, child.getParentId());
        assertEquals(0, child.getDepth());
        assertEquals(1, grandchild.getDepth());
        verify(deckMapper, times(2)).updateById(any(Deck.class));
    }

    @Test
    void moveRejectsSubtreeThatWouldExceedThreeLevels() {
        DeckMapper deckMapper = mock(DeckMapper.class);
        FlashcardMapper cardMapper = mock(FlashcardMapper.class);
        DeckServiceImpl service = new DeckServiceImpl(deckMapper, cardMapper, mock(FsrsMemoryService.class));
        Deck targetParent = deck(10L, null, 1);
        Deck movingRoot = deck(20L, null, 0);
        Deck movingChild = deck(21L, 20L, 1);
        when(deckMapper.selectList(any())).thenReturn(List.of(targetParent, movingRoot, movingChild));

        IllegalArgumentException error = assertThrows(
                IllegalArgumentException.class, () -> service.move(20L, 10L, 7L));

        assertTrue(error.getMessage().contains("三级"));
        verify(deckMapper, never()).updateById(any(Deck.class));
    }

    @Test
    void createUsesSelectedParentAndDerivedDepth() {
        DeckMapper deckMapper = mock(DeckMapper.class);
        FlashcardMapper cardMapper = mock(FlashcardMapper.class);
        DeckServiceImpl service = new DeckServiceImpl(deckMapper, cardMapper, mock(FsrsMemoryService.class));
        Deck parent = deck(10L, null, 1);
        when(deckMapper.selectById(10L)).thenReturn(parent);
        when(cardMapper.selectList(any())).thenReturn(List.of());
        DeckRequest request = new DeckRequest();
        request.setTitle("new-node");
        request.setParentId(10L);

        service.create(request, 7L);

        ArgumentCaptor<Deck> captor = ArgumentCaptor.forClass(Deck.class);
        verify(deckMapper).insert(captor.capture());
        assertEquals(10L, captor.getValue().getParentId());
        assertEquals(2, captor.getValue().getDepth());
        assertEquals(7L, captor.getValue().getUserId());
    }

    private Deck deck(Long id, Long parentId) {
        return deck(id, parentId, parentId == null ? 0 : 1);
    }

    private Deck deck(Long id, Long parentId, int depth) {
        Deck deck = new Deck();
        deck.setId(id);
        deck.setParentId(parentId);
        deck.setDepth(depth);
        deck.setUserId(7L);
        deck.setTitle("deck-" + id);
        deck.setType("test");
        deck.setCategory("test");
        return deck;
    }

    private Flashcard card(Long id, Long deckId, int reviewCount, LocalDateTime nextReviewAt) {
        Flashcard card = new Flashcard();
        card.setId(id);
        card.setDeckId(deckId);
        card.setReviewCount(reviewCount);
        card.setNextReviewAt(nextReviewAt);
        return card;
    }
}
