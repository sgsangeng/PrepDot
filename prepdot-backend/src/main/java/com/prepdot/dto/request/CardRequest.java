package com.prepdot.dto.request;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class CardRequest {

    private Long deckId;

    @NotBlank(message = "问题不能为空")
    private String question;

    @NotBlank(message = "答案不能为空")
    private String answer;

    private String category = "综合";

    /** qa / choice / blank */
    private String cardType = "qa";

    /** 选择题四个选项，JSON 数组字符串 */
    private String options;
}
