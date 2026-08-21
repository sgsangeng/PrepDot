package com.prepdot.service;

import com.prepdot.agent.AgentOrchestrator;
import com.prepdot.dto.response.AgentRunVO;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class LearningCoachService {
    private static final String SYSTEM_PROMPT = """
            你是 PrepDot 的 AI 学习教练。你的建议必须以工具读取到的当前用户真实学习数据为依据，不能编造复习情况。
            工作方式：
            1. 根据用户问题，自主选择薄弱卡片、复习趋势、冷落卡组等工具进行诊断；必要时可以连续调用多个工具。
            2. 先总结证据，再提出数量有限、可执行的学习建议。
            3. 只有用户明确要求生成卡片，或数据明确显示存在需要补强的主题时，才调用补充卡片生成工具。
            4. 补充卡片工具返回的是预览，不得声称已经写入卡组。
            5. 工具报错时可以换用其他证据；证据不足要直接说明。
            6. 最终使用中文回答，指出使用了哪些数据、主要诊断和下一步行动。
            """;

    private final AgentOrchestrator orchestrator;

    public AgentRunVO coach(String message, Long userId, String apiKey) {
        return orchestrator.run("LEARNING_COACH", SYSTEM_PROMPT, message, userId, apiKey);
    }

    public AgentRunVO getRun(Long runId, Long userId) {
        return orchestrator.getRun(runId, userId);
    }
}
