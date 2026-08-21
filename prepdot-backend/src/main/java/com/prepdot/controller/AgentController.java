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

@Tag(name = "AI 学习教练")
@RestController
@RequestMapping("/api/agent")
@RequiredArgsConstructor
public class AgentController {
    private final LearningCoachService coachService;

    @Operation(summary = "运行学习教练 Agent")
    @PostMapping("/coach")
    public Result<AgentRunVO> coach(@Valid @RequestBody CoachRequest request) {
        return Result.success(coachService.coach(request.getMessage(), UserContext.getUserId(), request.getCustomKey()));
    }

    @Operation(summary = "回放 Agent 执行轨迹")
    @GetMapping("/runs/{runId}")
    public Result<AgentRunVO> getRun(@PathVariable Long runId) {
        return Result.success(coachService.getRun(runId, UserContext.getUserId()));
    }
}
