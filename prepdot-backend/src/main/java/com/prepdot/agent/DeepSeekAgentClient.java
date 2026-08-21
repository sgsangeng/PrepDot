package com.prepdot.agent;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.prepdot.agent.model.AgentMessage;
import com.prepdot.agent.model.AgentModelResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

@Component
public class DeepSeekAgentClient implements AgentModelClient {
    private final ObjectMapper mapper;
    private final HttpClient httpClient;

    @Value("${ai.deepseek.api-url}") private String apiUrl;
    @Value("${ai.deepseek.system-key:}") private String systemKey;
    @Value("${ai.deepseek.model:deepseek-chat}") private String model;

    public DeepSeekAgentClient(ObjectMapper mapper) {
        this.mapper = mapper;
        this.httpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(30)).build();
    }

    @Override
    public AgentModelResponse chat(List<AgentMessage> messages, List<AgentTool> tools, String customKey) throws Exception {
        ObjectNode body = mapper.createObjectNode();
        body.put("model", model);
        body.set("messages", serializeMessages(messages));
        body.put("temperature", 0.2);
        body.put("max_tokens", 4096);
        if (!tools.isEmpty()) {
            ArrayNode definitions = body.putArray("tools");
            for (AgentTool tool : tools) {
                ObjectNode wrapper = definitions.addObject();
                wrapper.put("type", "function");
                ObjectNode function = wrapper.putObject("function");
                function.put("name", tool.name());
                function.put("description", tool.description());
                function.set("parameters", tool.parameters());
            }
            body.put("tool_choice", "auto");
        }

        String raw = post(body, customKey);
        JsonNode message = mapper.readTree(raw).path("choices").path(0).path("message");
        String content = message.path("content").isNull() ? "" : message.path("content").asText("");
        List<AgentMessage.ToolCall> calls = new ArrayList<>();
        for (JsonNode call : message.path("tool_calls")) {
            JsonNode function = call.path("function");
            JsonNode arguments;
            try {
                arguments = mapper.readTree(function.path("arguments").asText("{}"));
            } catch (Exception ignored) {
                arguments = mapper.createObjectNode();
            }
            calls.add(new AgentMessage.ToolCall(call.path("id").asText(), function.path("name").asText(), arguments));
        }
        return new AgentModelResponse(content, calls, raw);
    }

    @Override
    public String complete(String systemPrompt, String userPrompt, String customKey) throws Exception {
        return chat(List.of(AgentMessage.system(systemPrompt), AgentMessage.user(userPrompt)), List.of(), customKey).content();
    }

    private ArrayNode serializeMessages(List<AgentMessage> messages) {
        ArrayNode result = mapper.createArrayNode();
        for (AgentMessage message : messages) {
            ObjectNode node = result.addObject();
            node.put("role", message.role());
            if (message.content() == null) node.putNull("content"); else node.put("content", message.content());
            if (message.toolCallId() != null) node.put("tool_call_id", message.toolCallId());
            if (message.toolCalls() != null && !message.toolCalls().isEmpty()) {
                ArrayNode calls = node.putArray("tool_calls");
                for (AgentMessage.ToolCall call : message.toolCalls()) {
                    ObjectNode callNode = calls.addObject();
                    callNode.put("id", call.id());
                    callNode.put("type", "function");
                    ObjectNode function = callNode.putObject("function");
                    function.put("name", call.name());
                    try { function.put("arguments", mapper.writeValueAsString(call.arguments())); }
                    catch (Exception e) { function.put("arguments", "{}"); }
                }
            }
        }
        return result;
    }

    private String post(ObjectNode body, String customKey) throws Exception {
        String key = customKey != null && !customKey.isBlank() ? customKey : systemKey;
        if (key == null || key.isBlank()) throw new IllegalStateException("未配置 DeepSeek API Key");
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(apiUrl))
                .header("Content-Type", "application/json")
                .header("Authorization", "Bearer " + key)
                .timeout(Duration.ofSeconds(120))
                .POST(HttpRequest.BodyPublishers.ofString(mapper.writeValueAsString(body), StandardCharsets.UTF_8))
                .build();
        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() != 200) {
            throw new IllegalStateException("DeepSeek 调用失败(" + response.statusCode() + "): " + abbreviate(response.body(), 500));
        }
        return response.body();
    }

    private String abbreviate(String value, int max) {
        return value == null || value.length() <= max ? value : value.substring(0, max) + "...";
    }
}
