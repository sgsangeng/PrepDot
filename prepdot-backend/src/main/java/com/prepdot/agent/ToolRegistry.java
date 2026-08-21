package com.prepdot.agent;

import com.prepdot.common.BusinessException;
import org.springframework.stereotype.Component;

import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Component
public class ToolRegistry {
    private final Map<String, AgentTool> tools;

    public ToolRegistry(List<AgentTool> registeredTools) {
        Map<String, AgentTool> index = new LinkedHashMap<>();
        for (AgentTool tool : registeredTools) {
            if (index.putIfAbsent(tool.name(), tool) != null) {
                throw new IllegalStateException("重复的 Agent 工具名: " + tool.name());
            }
        }
        this.tools = Map.copyOf(index);
    }

    public AgentTool require(String name) {
        AgentTool tool = tools.get(name);
        if (tool == null) throw BusinessException.badRequest("模型请求了未注册工具: " + name);
        return tool;
    }

    public Collection<AgentTool> all() {
        return tools.values();
    }
}
