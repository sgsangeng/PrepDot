package com.prepdot.entity;

import com.baomidou.mybatisplus.annotation.*;
import lombok.Data;

@Data
@TableName("daily_plan_item")
public class DailyPlanItem {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long planId;

    private Long cardId;

    /** pending / done */
    private String status;
}
