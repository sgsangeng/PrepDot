package com.prepdot.entity;

import com.baomidou.mybatisplus.annotation.*;
import lombok.Data;

import java.time.LocalDateTime;

@Data
@TableName("flashcard")
public class Flashcard {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long deckId;

    private String question;

    private String answer;

    /** 卡片类型：qa / choice / blank */
    private String cardType = "qa";

    /** 选择题选项（JSON 数组字符串），其他类型为 null */
    private String options;

    private String category;

    /** 记忆度 0-100 */
    private Integer memoryScore;

    /** 复习次数 */
    private Integer reviewCount;

    private LocalDateTime lastReviewedAt;

    /** 下次复习时间，到期才进入当日计划 */
    private LocalDateTime nextReviewAt;

    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createdAt;
}
