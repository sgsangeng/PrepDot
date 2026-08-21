package com.prepdot.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

@Data
@TableName("agent_step")
public class AgentStep {
    @TableId(type = IdType.AUTO)
    private Long id;
    private Long runId;
    private Integer stepNo;
    private String stepType;
    private String modelContent;
    private String toolName;
    private String toolArguments;
    private String toolResult;
    private Long durationMs;
    private LocalDateTime createdAt;
}
