package com.prepdot.agent;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.prepdot.agent.model.AgentMessage;
import com.prepdot.agent.model.AgentModelResponse;
import com.prepdot.dto.response.AgentRunVO;
import com.prepdot.entity.AgentRun;
import com.prepdot.entity.AgentStep;
import com.prepdot.mapper.AgentRunMapper;
import com.prepdot.mapper.AgentStepMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Service
@RequiredArgsConstructor
public class AgentOrchestrator {
    private final AgentModelClient modelClient;
    private final ToolRegistry toolRegistry;
    private final AgentRunMapper runMapper;
    private final AgentStepMapper stepMapper;
    private final ObjectMapper mapper;

    @Value("${ai.agent.max-iterations:8}") private int maxIterations;

    public AgentRunVO run(String taskType, String systemPrompt, String userInput, Long userId, String apiKey) {
        AgentRun run = new AgentRun();
        run.setUserId(userId);
        run.setTaskType(taskType);
        run.setInput(userInput);
        run.setStatus("RUNNING");
        run.setStepCount(0);
        run.setStartedAt(LocalDateTime.now());
        runMapper.insert(run);

        List<AgentMessage> messages = new ArrayList<>();
        messages.add(AgentMessage.system(systemPrompt));
        messages.add(AgentMessage.user(userInput));
        int stepNo = 0;
        try {
            for (int iteration = 0; iteration < maxIterations; iteration++) {
                long modelStarted = System.currentTimeMillis();
                AgentModelResponse response = modelClient.chat(messages, new ArrayList<>(toolRegistry.all()), apiKey);
                AgentStep modelStep = step(run.getId(), ++stepNo, "MODEL");
                modelStep.setModelContent(response.content());
                modelStep.setDurationMs(System.currentTimeMillis() - modelStarted);
                stepMapper.insert(modelStep);
                messages.add(AgentMessage.assistant(response.content(), response.toolCalls()));

                if (!response.hasToolCalls()) {
                    finish(run, "SUCCEEDED", response.content(), stepNo, null);
                    return toVO(run);
                }

                for (AgentMessage.ToolCall call : response.toolCalls()) {
                    AgentTool tool = toolRegistry.require(call.name());
                    long toolStarted = System.currentTimeMillis();
                    String result;
                    try {
                        result = tool.execute(call.arguments(), new AgentExecutionContext(userId, run.getId(), apiKey));
                    } catch (Exception e) {
                        result = "{\"error\":\"" + escape(e.getMessage()) + "\"}";
                    }
                    AgentStep toolStep = step(run.getId(), ++stepNo, "TOOL");
                    toolStep.setToolName(call.name());
                    toolStep.setToolArguments(mapper.writeValueAsString(call.arguments()));
                    toolStep.setToolResult(abbreviate(result, 12000));
                    toolStep.setDurationMs(System.currentTimeMillis() - toolStarted);
                    stepMapper.insert(toolStep);
                    messages.add(AgentMessage.tool(call.id(), result));
                }
            }
            throw new IllegalStateException("Agent 超过最大迭代次数 " + maxIterations);
        } catch (Exception e) {
            finish(run, "FAILED", null, stepNo, e.getMessage());
            throw new IllegalStateException("学习教练执行失败，runId=" + run.getId() + ": " + e.getMessage(), e);
        }
    }

    public AgentRunVO getRun(Long runId, Long userId) {
        AgentRun run = runMapper.selectById(runId);
        if (run == null || !run.getUserId().equals(userId)) {
            throw new IllegalArgumentException("Agent 运行记录不存在");
        }
        return toVO(run);
    }

    private AgentStep step(Long runId, int no, String type) {
        AgentStep step = new AgentStep();
        step.setRunId(runId);
        step.setStepNo(no);
        step.setStepType(type);
        step.setCreatedAt(LocalDateTime.now());
        return step;
    }

    private void finish(AgentRun run, String status, String output, int count, String error) {
        run.setStatus(status);
        run.setOutput(output);
        run.setStepCount(count);
        run.setErrorMessage(error);
        run.setFinishedAt(LocalDateTime.now());
        runMapper.updateById(run);
    }

    private AgentRunVO toVO(AgentRun run) {
        AgentRunVO vo = new AgentRunVO();
        vo.setRunId(run.getId());
        vo.setStatus(run.getStatus());
        vo.setOutput(run.getOutput());
        vo.setStepCount(run.getStepCount() == null ? 0 : run.getStepCount());
        List<AgentStep> steps = stepMapper.selectList(new LambdaQueryWrapper<AgentStep>()
                .eq(AgentStep::getRunId, run.getId()).orderByAsc(AgentStep::getStepNo));
        vo.setSteps(steps.stream().map(this::toStepVO).toList());
        return vo;
    }

    private AgentRunVO.StepVO toStepVO(AgentStep step) {
        AgentRunVO.StepVO vo = new AgentRunVO.StepVO();
        vo.setStepNo(step.getStepNo());
        vo.setStepType(step.getStepType());
        vo.setModelContent(step.getModelContent());
        vo.setToolName(step.getToolName());
        vo.setToolArguments(step.getToolArguments());
        vo.setToolResult(step.getToolResult());
        vo.setDurationMs(step.getDurationMs());
        return vo;
    }

    private String abbreviate(String value, int max) {
        return value == null || value.length() <= max ? value : value.substring(0, max) + "...";
    }

    private String escape(String value) {
        if (value == null) return "unknown";
        return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", " ");
    }
}
