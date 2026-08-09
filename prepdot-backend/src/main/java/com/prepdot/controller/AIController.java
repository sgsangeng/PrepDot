package com.prepdot.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.prepdot.common.Result;
import com.prepdot.common.UserContext;
import com.prepdot.dto.response.DeckVO;
import com.prepdot.dto.response.KnowledgeGraphVO;
import com.prepdot.service.AIService;
import com.prepdot.service.DeckService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

/**
 * AI 相关接口
 *
 * POST /api/ai/generate   上传文件 → AI 生成卡组 JSON 预览（不入库）
 * POST /api/ai/import     将层级 JSON 直接入库
 */
@Slf4j
@Tag(name = "AI 生成")
@RestController
@RequestMapping("/api/ai")
@RequiredArgsConstructor
public class AIController {

    private final AIService   aiService;
    private final DeckService deckService;
    private final ObjectMapper mapper = new ObjectMapper();

    /**
     * 上传文件，返回 AI 生成的层级卡组 JSON 字符串（用于 iOS 端预览）
     *
     * @param file       上传的文件（txt/pdf/docx/pptx/md）
     * @param deckTitle  用户指定的根卡组名称
     * @param customKey  用户自己的 DeepSeek API Key（可选）
     * @param cardCount  期望总卡片数（影响 Prompt）
     * @param detailHint 答案详细程度描述（影响 Prompt）
     */
    @Operation(summary = "上传文件 → AI 生成卡组 JSON（预览，不入库）")
    @PostMapping("/generate")
    public Result<String> generate(
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "deckTitle", defaultValue = "AI 生成卡组") String deckTitle,
            @RequestParam(value = "customKey", required = false) String customKey,
            @RequestParam(value = "cardCount", defaultValue = "10") int cardCount,
            @RequestParam(value = "detailHint", defaultValue = "答案简洁，不超过50字") String detailHint
    ) {
        try {
            log.info("AI 生成请求：file={}, title={}, cardCount={}", file.getOriginalFilename(), deckTitle, cardCount);
            String text = aiService.extractText(file);
            log.info("提取文本长度：{}", text.length());

            String json = aiService.generateDeckJson(text, deckTitle, customKey, cardCount, detailHint);
            log.info("AI 生成 JSON 长度：{}", json.length());

            return Result.success(json);
        } catch (IllegalStateException e) {
            return Result.error(e.getMessage());
        } catch (Exception e) {
            log.error("AI 生成失败", e);
            return Result.error("AI 生成失败：" + e.getMessage());
        }
    }

    /**
     * 将层级卡组 JSON 入库（AI 生成或手动编写的 JSON 均可）
     */
    @Operation(summary = "生成知识图谱")
    @GetMapping("/knowledge-graph")
    public Result<KnowledgeGraphVO> knowledgeGraph(
            @RequestParam(required = false, defaultValue = "") String customKey) {
        try {
            return Result.success(aiService.generateKnowledgeGraph(customKey));
        } catch (Exception e) {
            log.error("知识图谱生成失败", e);
            return Result.error("知识图谱生成失败：" + e.getMessage());
        }
    }

    @Operation(summary = "导入层级卡组 JSON → 入库")
    @PostMapping("/import")
    public Result<DeckVO> importJson(@RequestBody String rawJson) {
        try {
            JsonNode root = mapper.readTree(rawJson);
            DeckVO vo = deckService.createHierarchical(root, UserContext.getUserId());
            return Result.success(vo);
        } catch (Exception e) {
            log.error("JSON 导入失败", e);
            return Result.error("JSON 格式错误：" + e.getMessage());
        }
    }
}
