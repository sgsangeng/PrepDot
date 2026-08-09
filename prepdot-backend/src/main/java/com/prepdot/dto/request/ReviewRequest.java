package com.prepdot.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

@Data
public class ReviewRequest {

    @NotNull(message = "卡片 ID 不能为空")
    private Long cardId;

    /** again / hard / good / easy */
    @NotBlank(message = "评分不能为空")
    private String rating;
}
