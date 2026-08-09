package com.prepdot.entity;

import com.baomidou.mybatisplus.annotation.*;
import lombok.Data;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Data
@TableName("daily_plan")
public class DailyPlan {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long userId;

    private LocalDate planDate;

    private Integer totalCount;

    private Integer completedCount;

    private Integer estimatedMinutes;

    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createdAt;
}
