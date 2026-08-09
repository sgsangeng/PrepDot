package com.prepdot.controller;

import com.prepdot.common.Result;
import com.prepdot.common.UserContext;
import com.prepdot.dto.request.ReviewRequest;
import com.prepdot.dto.response.TodayPlanVO;
import com.prepdot.entity.Flashcard;
import com.prepdot.service.PlanService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

@Tag(name = "每日计划 & 复习")
@RestController
@RequestMapping("/api/plan")
@RequiredArgsConstructor
public class PlanController {

    private final PlanService planService;

    @Operation(summary = "获取今日复习计划（不存在时自动生成）")
    @GetMapping("/today")
    public Result<TodayPlanVO> today() {
        return Result.success(planService.getTodayPlan(UserContext.getUserId()));
    }

    @Operation(summary = "提交复习打分（only again/hard/good/easy）")
    @PostMapping("/review")
    public Result<Flashcard> review(@Valid @RequestBody ReviewRequest request) {
        return Result.success(planService.submitReview(request, UserContext.getUserId()));
    }
}
