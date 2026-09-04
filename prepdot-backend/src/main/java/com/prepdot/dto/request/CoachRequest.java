package com.prepdot.dto.request;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class CoachRequest {
    @NotBlank(message = "请填写希望学习教练解决的问题")
    private String message;
    private String customKey;
    /** CARD_QA：针对当前卡片快速答疑；省略时使用完整学习诊断模式。 */
    private String mode;
}
