package com.prepdot.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.MybatisConfiguration;
import com.baomidou.mybatisplus.core.metadata.TableInfoHelper;
import com.prepdot.entity.Deck;
import com.prepdot.entity.Flashcard;
import com.prepdot.mapper.DeckMapper;
import com.prepdot.mapper.FlashcardMapper;
import com.prepdot.service.impl.DeckServiceImpl;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.apache.ibatis.builder.MapperBuilderAssistant;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
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

    private Deck deck(Long id, Long parentId) {
        Deck deck = new Deck();
        deck.setId(id);
        deck.setParentId(parentId);
        return deck;
    }
}
