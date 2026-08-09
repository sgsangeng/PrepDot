package com.prepdot.service;

import com.prepdot.dto.request.ReviewRequest;
import com.prepdot.dto.response.TodayPlanVO;
import com.prepdot.entity.Flashcard;

public interface PlanService {

    TodayPlanVO getTodayPlan(Long userId);

    Flashcard submitReview(ReviewRequest request, Long userId);
}
