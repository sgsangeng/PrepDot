package com.prepdot.entity;

import com.baomidou.mybatisplus.annotation.*;
import lombok.Data;
import java.time.LocalDateTime;

@Data
@TableName("`user`")   // user 是 MySQL 保留字，需要反引号
public class User {

    @TableId(type = IdType.AUTO)
    private Long id;

    private String username;
    private String nickname;
    private String password;
    private String avatarColor;
    private Integer studyTarget;

    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createdAt;
}
