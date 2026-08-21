package com.prepdot.agent;

import com.prepdot.agent.model.AgentMessage;
import com.prepdot.agent.model.AgentModelResponse;

import java.util.List;

public interface AgentModelClient {
    AgentModelResponse chat(List<AgentMessage> messages, List<AgentTool> tools, String apiKey) throws Exception;
    String complete(String systemPrompt, String userPrompt, String apiKey) throws Exception;
}
