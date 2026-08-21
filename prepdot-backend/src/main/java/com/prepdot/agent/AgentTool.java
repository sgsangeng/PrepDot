package com.prepdot.agent;

import com.fasterxml.jackson.databind.JsonNode;

public interface AgentTool {
    String name();
    String description();
    JsonNode parameters();
    String execute(JsonNode arguments, AgentExecutionContext context) throws Exception;
}
