package com.prepdot.controller;

import com.prepdot.common.Result;
import com.prepdot.common.UserContext;
import com.prepdot.dto.request.CoachRequest;
import com.prepdot.dto.response.AgentRunVO;
import com.prepdot.service.LearningCoachService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;
import java.util.concurrent.CompletableFuture;

@Tag(name = "AI 学习教练")
@RestController
@RequestMapping("/api/agent")
@RequiredArgsConstructor
public class AgentController {
    private final LearningCoachService coachService;

    @Operation(summary = "运行学习教练 Agent")
    @PostMapping("/coach")
    public Result<AgentRunVO> coach(@Valid @RequestBody CoachRequest request) {
        return Result.success(coachService.coach(
                request.getMessage(), request.getMode(), UserContext.getUserId(), request.getCustomKey()));
    }

    @Operation(summary = "流式运行学习教练 Agent")
    @PostMapping(value = "/coach/stream", produces = "text/event-stream")
    public SseEmitter coachStream(@Valid @RequestBody CoachRequest request) {
        Long userId = UserContext.getUserId();
        SseEmitter emitter = new SseEmitter(180_000L);
        CompletableFuture.runAsync(() -> {
            try {
                AgentRunVO result = coachService.coach(request.getMessage(), request.getMode(), userId,
                        request.getCustomKey(), text -> send(emitter, "progress", text));
                emitter.send(SseEmitter.event().name("result").data(result));
                emitter.complete();
            } catch (Exception e) {
                try { emitter.send(SseEmitter.event().name("error").data(e.getMessage())); }
                catch (Exception ignored) { }
                emitter.completeWithError(e);
            }
        });
        return emitter;
    }

    private void send(SseEmitter emitter, String event, Object data) {
        try { emitter.send(SseEmitter.event().name(event).data(data)); }
        catch (Exception ignored) { }
    }

    @Operation(summary = "回放 Agent 执行轨迹")
    @GetMapping("/runs/{runId}")
    public Result<AgentRunVO> getRun(@PathVariable Long runId) {
        return Result.success(coachService.getRun(runId, UserContext.getUserId()));
    }
}
