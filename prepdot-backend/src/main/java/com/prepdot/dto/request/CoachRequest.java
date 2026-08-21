package com.prepdot.dto.request;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class CoachRequest {
    @NotBlank(message = "请填写希望学习教练解决的问题")
    private String message;
    private String customKey;
}
