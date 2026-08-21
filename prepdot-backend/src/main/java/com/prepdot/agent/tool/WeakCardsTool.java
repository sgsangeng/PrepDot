package com.prepdot.agent.tool;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.prepdot.agent.AgentExecutionContext;
import com.prepdot.agent.AgentTool;
import com.prepdot.entity.Deck;
import com.prepdot.entity.Flashcard;
import com.prepdot.mapper.DeckMapper;
import com.prepdot.mapper.FlashcardMapper;
import com.prepdot.service.FsrsMemoryService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.Comparator;
import java.util.List;

@Component
@RequiredArgsConstructor
public class WeakCardsTool implements AgentTool {
    private final DeckMapper deckMapper;
    private final FlashcardMapper cardMapper;
    private final ObjectMapper mapper;
    private final FsrsMemoryService fsrsMemoryService;

    public String name() { return "get_weak_cards"; }
    public String description() { return "读取当前用户记忆最薄弱的卡片，包含卡组、记忆度、FSRS 稳定性和复习次数。"; }
    public JsonNode parameters() {
        return ToolSchemas.object(mapper, "{\"limit\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":30,\"description\":\"返回数量，默认10\"}}");
    }

    public String execute(JsonNode args, AgentExecutionContext context) throws Exception {
        int limit = Math.max(1, Math.min(30, args.path("limit").asInt(10)));
        List<Deck> decks = deckMapper.selectList(new LambdaQueryWrapper<Deck>().eq(Deck::getUserId, context.userId()));
        if (decks.isEmpty()) return "[]";
        var deckById = decks.stream().collect(java.util.stream.Collectors.toMap(Deck::getId, d -> d));
        List<Flashcard> cards = cardMapper.selectList(new LambdaQueryWrapper<Flashcard>()
                .in(Flashcard::getDeckId, deckById.keySet()));
        var now = java.time.LocalDateTime.now();
        cards.sort(Comparator
                .comparingInt((Flashcard c) -> fsrsMemoryService.currentScore(c, now))
                .thenComparing(c -> c.getStability() == null ? 0.0 : c.getStability()));
        var result = mapper.createArrayNode();
        cards.stream().limit(limit).forEach(card -> {
            var node = result.addObject();
            node.put("cardId", card.getId());
            node.put("deckId", card.getDeckId());
            node.put("deckTitle", deckById.get(card.getDeckId()).getTitle());
            node.put("question", card.getQuestion());
            node.put("memoryScore", fsrsMemoryService.currentScore(card, now));
            if (card.getDifficulty() != null) node.put("difficulty", card.getDifficulty());
            if (card.getStability() != null) node.put("stabilityDays", card.getStability());
            node.put("reviewCount", card.getReviewCount() == null ? 0 : card.getReviewCount());
        });
        return mapper.writeValueAsString(result);
    }
}
