package com.prepdot.entity;

import com.baomidou.mybatisplus.annotation.*;
import lombok.Data;

import java.time.LocalDateTime;

@Data
@TableName("deck")
public class Deck {

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 所属用户 ID */
    private Long userId;

    /** 父卡组 ID，null 表示根卡组 */
    private Long parentId;

    /** 层级深度：0=根，1=子，2=孙（最大 2） */
    private Integer depth;

    private String title;

    private String type;

    private String category;

    private String description;

    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createdAt;

    @TableField(fill = FieldFill.INSERT_UPDATE)
    private LocalDateTime updatedAt;
}
