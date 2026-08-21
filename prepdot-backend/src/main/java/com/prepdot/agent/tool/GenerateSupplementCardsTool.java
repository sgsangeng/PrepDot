package com.prepdot.agent.tool;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.prepdot.agent.AgentExecutionContext;
import com.prepdot.agent.AgentTool;
import com.prepdot.agent.GeneratorCriticService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
public class GenerateSupplementCardsTool implements AgentTool {
    private final GeneratorCriticService generatorCriticService;
    private final ObjectMapper mapper;

    public String name() { return "generate_supplement_cards"; }
    public String description() { return "针对诊断出的薄弱主题生成补充闪卡；生成结果会经过 Critic 质检，不合格会携带反馈自动重写。仅返回预览，不自动入库。"; }
    public JsonNode parameters() {
        return ToolSchemas.object(mapper, """
                {
                  "topic":{"type":"string","minLength":1,"description":"需要补强的具体主题"},
                  "count":{"type":"integer","minimum":1,"maximum":10,"description":"生成数量，默认5"},
                  "weaknessContext":{"type":"string","description":"从诊断工具结果中总结的用户薄弱点"}
                }
                """, "topic", "weaknessContext");
    }

    public String execute(JsonNode args, AgentExecutionContext context) throws Exception {
        String topic = args.path("topic").asText("").trim();
        if (topic.isBlank()) throw new IllegalArgumentException("topic 不能为空");
        int count = Math.max(1, Math.min(10, args.path("count").asInt(5)));
        JsonNode result = generatorCriticService.generate(topic, count,
                args.path("weaknessContext").asText(""), context.apiKey());
        return mapper.writeValueAsString(result);
    }
}
