package com.prepdot.agent.tool;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.prepdot.agent.AgentExecutionContext;
import com.prepdot.agent.AgentTool;
import com.prepdot.entity.ReviewRecord;
import com.prepdot.mapper.ReviewRecordMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;

@Component
@RequiredArgsConstructor
public class ReviewTrendTool implements AgentTool {
    private final ReviewRecordMapper reviewMapper;
    private final ObjectMapper mapper;

    public String name() { return "get_review_trend"; }
    public String description() { return "统计当前用户最近若干天每天的复习量以及 again/hard/good/easy 分布。"; }
    public JsonNode parameters() {
        return ToolSchemas.object(mapper, "{\"days\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":60,\"description\":\"统计天数，默认14\"}}");
    }

    public String execute(JsonNode args, AgentExecutionContext context) throws Exception {
        int days = Math.max(1, Math.min(60, args.path("days").asInt(14)));
        LocalDate start = LocalDate.now().minusDays(days - 1L);
        var records = reviewMapper.selectList(new LambdaQueryWrapper<ReviewRecord>()
                .eq(ReviewRecord::getUserId, context.userId())
                .ge(ReviewRecord::getReviewedAt, start.atStartOfDay())
                .orderByAsc(ReviewRecord::getReviewedAt));
        var byDate = new LinkedHashMap<LocalDate, int[]>();
        for (int i = 0; i < days; i++) byDate.put(start.plusDays(i), new int[5]);
        for (ReviewRecord record : records) {
            LocalDateTime time = record.getReviewedAt();
            if (time == null) continue;
            int[] counts = byDate.get(time.toLocalDate());
            if (counts == null) continue;
            counts[0]++;
            int index = switch (record.getRating()) { case "again" -> 1; case "hard" -> 2; case "good" -> 3; case "easy" -> 4; default -> -1; };
            if (index > 0) counts[index]++;
        }
        var result = mapper.createArrayNode();
        byDate.forEach((date, c) -> {
            var node = result.addObject();
            node.put("date", date.toString()); node.put("total", c[0]); node.put("again", c[1]);
            node.put("hard", c[2]); node.put("good", c[3]); node.put("easy", c[4]);
        });
        return mapper.writeValueAsString(result);
    }
}
