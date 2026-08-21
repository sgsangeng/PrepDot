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
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.util.Comparator;

@Component
@RequiredArgsConstructor
public class NeglectedDecksTool implements AgentTool {
    private final DeckMapper deckMapper;
    private final FlashcardMapper cardMapper;
    private final ObjectMapper mapper;

    public String name() { return "get_neglected_decks"; }
    public String description() { return "查找当前用户长期未复习或从未复习的卡组。"; }
    public JsonNode parameters() {
        return ToolSchemas.object(mapper, "{\"limit\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":20}}");
    }

    public String execute(JsonNode args, AgentExecutionContext context) throws Exception {
        int limit = Math.max(1, Math.min(20, args.path("limit").asInt(8)));
        var decks = deckMapper.selectList(new LambdaQueryWrapper<Deck>().eq(Deck::getUserId, context.userId()));
        var rows = new java.util.ArrayList<Row>();
        for (Deck deck : decks) {
            var cards = cardMapper.selectList(new LambdaQueryWrapper<Flashcard>().eq(Flashcard::getDeckId, deck.getId()));
            LocalDateTime last = cards.stream().map(Flashcard::getLastReviewedAt).filter(java.util.Objects::nonNull)
                    .max(Comparator.naturalOrder()).orElse(null);
            rows.add(new Row(deck, cards.size(), last));
        }
        rows.sort(Comparator.comparing(Row::lastReviewed, Comparator.nullsFirst(Comparator.naturalOrder())));
        var result = mapper.createArrayNode();
        rows.stream().limit(limit).forEach(row -> {
            var node = result.addObject();
            node.put("deckId", row.deck().getId()); node.put("title", row.deck().getTitle()); node.put("cardCount", row.cardCount());
            if (row.lastReviewed() == null) node.putNull("lastReviewedAt"); else node.put("lastReviewedAt", row.lastReviewed().toString());
        });
        return mapper.writeValueAsString(result);
    }

    private record Row(Deck deck, int cardCount, LocalDateTime lastReviewed) {}
}
