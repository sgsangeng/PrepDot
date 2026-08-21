package com.prepdot.agent;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class GeneratorCriticServiceTest {
    @Test
    void generate_rewritesWithCriticFeedbackUntilApproved() throws Exception {
        AgentModelClient client = mock(AgentModelClient.class);
        when(client.complete(anyString(), anyString(), anyString())).thenReturn(
                "[{\"question\":\"Q1\",\"answer\":\"A1\",\"category\":\"综合\"}]",
                "{\"approved\":false,\"feedback\":\"分类过于笼统\",\"issues\":[\"分类\"]}",
                "[{\"question\":\"Q1\",\"answer\":\"A1具体解释\",\"category\":\"JVM内存\"}]",
                "{\"approved\":true,\"feedback\":\"\",\"issues\":[]}"
        );
        GeneratorCriticService service = new GeneratorCriticService(client, new ObjectMapper());
        ReflectionTestUtils.setField(service, "maxRetries", 2);

        var result = service.generate("JVM", 1, "用户经常答错内存区域", "key");

        assertTrue(result.path("approved").asBoolean());
        assertEquals(2, result.path("attempts").asInt());
        assertEquals("JVM内存", result.path("cards").path(0).path("category").asText());
    }
}
