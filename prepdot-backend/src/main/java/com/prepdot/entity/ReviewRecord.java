package com.prepdot.entity;

import com.baomidou.mybatisplus.annotation.*;
import lombok.Data;

import java.time.LocalDateTime;

@Data
@TableName("review_record")
public class ReviewRecord {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long userId;

    private Long cardId;

    /** again / hard / good / easy */
    private String rating;

    private Integer memoryScoreBefore;

    private Integer memoryScoreAfter;

    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime reviewedAt;
}
