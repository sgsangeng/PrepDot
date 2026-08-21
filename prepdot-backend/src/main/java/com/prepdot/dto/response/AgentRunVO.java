package com.prepdot.dto.response;

import lombok.Data;

import java.util.List;

@Data
public class AgentRunVO {
    private Long runId;
    private String status;
    private String output;
    private int stepCount;
    private List<StepVO> steps;

    @Data
    public static class StepVO {
        private int stepNo;
        private String stepType;
        private String modelContent;
        private String toolName;
        private String toolArguments;
        private String toolResult;
        private Long durationMs;
    }
}
