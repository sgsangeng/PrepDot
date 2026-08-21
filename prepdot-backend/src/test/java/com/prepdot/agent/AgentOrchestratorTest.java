package com.prepdot.agent;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.prepdot.agent.model.AgentMessage;
import com.prepdot.agent.model.AgentModelResponse;
import com.prepdot.entity.AgentRun;
import com.prepdot.entity.AgentStep;
import com.prepdot.mapper.AgentRunMapper;
import com.prepdot.mapper.AgentStepMapper;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class AgentOrchestratorTest {
    private final ObjectMapper mapper = new ObjectMapper();

    @Test
    void run_executesToolThenReturnsFinalAnswerAndPersistsTrace() throws Exception {
        AgentModelClient client = mock(AgentModelClient.class);
        AgentRunMapper runMapper = mock(AgentRunMapper.class);
        AgentStepMapper stepMapper = mock(AgentStepMapper.class);
        doAnswer(invocation -> { ((AgentRun) invocation.getArgument(0)).setId(42L); return 1; })
                .when(runMapper).insert(any(AgentRun.class));
        when(stepMapper.selectList(any())).thenReturn(List.of());

        AgentMessage.ToolCall call = new AgentMessage.ToolCall("call-1", "echo", mapper.readTree("{\"value\":\"data\"}"));
        when(client.chat(anyList(), anyList(), any())).thenReturn(
                new AgentModelResponse("", List.of(call), "raw-1"),
                new AgentModelResponse("根据工具数据得出结论", List.of(), "raw-2")
        );
        AgentTool echo = new AgentTool() {
            public String name() { return "echo"; }
            public String description() { return "test"; }
            public JsonNode parameters() { return mapper.createObjectNode(); }
            public String execute(JsonNode arguments, AgentExecutionContext context) { return "result:" + arguments.path("value").asText(); }
        };
        AgentOrchestrator orchestrator = new AgentOrchestrator(client, new ToolRegistry(List.of(echo)), runMapper, stepMapper, mapper);
        ReflectionTestUtils.setField(orchestrator, "maxIterations", 4);

        var result = orchestrator.run("TEST", "system", "question", 7L, "key");

        assertEquals("SUCCEEDED", result.getStatus());
        assertEquals("根据工具数据得出结论", result.getOutput());
        assertEquals(3, result.getStepCount());
        verify(stepMapper, times(3)).insert(any(AgentStep.class));
        verify(runMapper).updateById(org.mockito.ArgumentMatchers.<AgentRun>argThat(
                run -> "SUCCEEDED".equals(run.getStatus()) && run.getStepCount() == 3));
    }
}
