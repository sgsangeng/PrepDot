package com.prepdot.agent.model;

import java.util.List;

public record AgentModelResponse(String content, List<AgentMessage.ToolCall> toolCalls, String rawResponse) {
    public boolean hasToolCalls() { return toolCalls != null && !toolCalls.isEmpty(); }
}
