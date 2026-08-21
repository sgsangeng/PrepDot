package com.prepdot.agent.tool;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

final class ToolSchemas {
    private ToolSchemas() {}

    static JsonNode object(ObjectMapper mapper, String propertiesJson, String... required) {
        try {
            var root = mapper.createObjectNode();
            root.put("type", "object");
            root.set("properties", mapper.readTree(propertiesJson));
            var requiredNode = root.putArray("required");
            for (String item : required) requiredNode.add(item);
            root.put("additionalProperties", false);
            return root;
        } catch (Exception e) {
            throw new IllegalArgumentException("工具 Schema 配置错误", e);
        }
    }
}
