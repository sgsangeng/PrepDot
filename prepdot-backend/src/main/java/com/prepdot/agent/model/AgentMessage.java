package com.prepdot.agent.model;

import com.fasterxml.jackson.databind.JsonNode;

import java.util.List;

public record AgentMessage(String role, String content, String toolCallId, List<ToolCall> toolCalls) {
    public static AgentMessage system(String content) { return new AgentMessage("system", content, null, null); }
    public static AgentMessage user(String content) { return new AgentMessage("user", content, null, null); }
    public static AgentMessage assistant(String content, List<ToolCall> calls) { return new AgentMessage("assistant", content, null, calls); }
    public static AgentMessage tool(String callId, String content) { return new AgentMessage("tool", content, callId, null); }

    public record ToolCall(String id, String name, JsonNode arguments) {}
}
