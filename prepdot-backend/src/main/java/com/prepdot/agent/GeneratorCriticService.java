package com.prepdot.agent;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class GeneratorCriticService {
    private final AgentModelClient modelClient;
    private final ObjectMapper mapper;

    @Value("${ai.agent.critic-max-retries:2}") private int maxRetries;

    public JsonNode generate(String topic, int count, String context, String apiKey) throws Exception {
        String feedback = "无";
        JsonNode lastDraft = mapper.createArrayNode();
        for (int attempt = 0; attempt <= maxRetries; attempt++) {
            String draftText = modelClient.complete(
                    "你是学习闪卡生成器。只输出 JSON，不要 Markdown。",
                    generatorPrompt(topic, count, context, feedback), apiKey);
            lastDraft = parseJson(draftText);
            validateDraftShape(lastDraft, count);

            String criticText = modelClient.complete(
                    "你是严格的闪卡质量审查员。只输出 JSON，不要 Markdown。",
                    criticPrompt(topic, lastDraft), apiKey);
            JsonNode verdict = parseJson(criticText);
            if (verdict.path("approved").asBoolean(false)) {
                var result = mapper.createObjectNode();
                result.put("approved", true);
                result.put("attempts", attempt + 1);
                result.set("cards", lastDraft);
                result.set("critic", verdict);
                return result;
            }
            feedback = verdict.path("feedback").asText("内容不够具体，请减少重复并提高答案完整性");
        }
        var result = mapper.createObjectNode();
        result.put("approved", false);
        result.put("attempts", maxRetries + 1);
        result.put("reason", "达到最大质检重试次数");
        result.set("cards", lastDraft);
        return result;
    }

    private String generatorPrompt(String topic, int count, String context, String feedback) {
        return """
                围绕主题“%s”生成 %d 张针对性补充闪卡。
                用户薄弱点上下文：%s
                上一轮审查反馈：%s
                每张卡只考察一个知识点，答案具体且可独立理解；分类应具体且有区分度。
                严格输出 JSON 数组：[{
                  "question":"问题", "answer":"答案", "category":"具体分类", "reason":"为什么适合该用户"
                }]
                """.formatted(topic, count, context, feedback);
    }

    private String criticPrompt(String topic, JsonNode cards) throws Exception {
        return """
                审查主题“%s”的以下闪卡：%s
                标准：问题不重复；分类不能全部雷同或过于笼统；答案不能空洞；每张卡聚焦一个知识点；内容与主题及薄弱点有关。
                严格输出：{"approved":true或false,"feedback":"若不通过，给出可直接用于重写的具体意见","issues":["问题"]}
                """.formatted(topic, mapper.writeValueAsString(cards));
    }

    private JsonNode parseJson(String raw) throws Exception {
        String text = raw == null ? "" : raw.trim();
        if (text.startsWith("```")) text = text.replaceFirst("```[a-zA-Z]*\\s*", "").replaceFirst("```\\s*$", "");
        return mapper.readTree(text);
    }

    private void validateDraftShape(JsonNode draft, int count) {
        if (!draft.isArray() || draft.isEmpty()) throw new IllegalStateException("生成器未返回卡片数组");
        if (draft.size() > count + 2) throw new IllegalStateException("生成卡片数量明显超出请求");
        for (JsonNode card : draft) {
            if (card.path("question").asText().isBlank() || card.path("answer").asText().isBlank()) {
                throw new IllegalStateException("生成卡片缺少 question 或 answer");
            }
        }
    }
}
