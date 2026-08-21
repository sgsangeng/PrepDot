package com.prepdot.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.prepdot.dto.response.KnowledgeGraphVO;
import com.prepdot.entity.Deck;
import com.prepdot.entity.Flashcard;
import com.prepdot.mapper.DeckMapper;
import com.prepdot.mapper.FlashcardMapper;
import lombok.extern.slf4j.Slf4j;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.text.PDFTextStripper;
import org.apache.poi.xslf.usermodel.*;
import org.apache.poi.xwpf.usermodel.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import com.prepdot.service.FsrsMemoryService;

import java.io.*;
import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
import java.util.stream.Collectors;

/**
 * AI 服务：文件解析 + DeepSeek API 调用
 */
@Slf4j
@Service
public class AIService {

    @Value("${ai.deepseek.api-url}")
    private String apiUrl;

    @Value("${ai.deepseek.system-key:}")
    private String systemKey;

    @Value("${ai.deepseek.model:deepseek-chat}")
    private String defaultModel;

    @Autowired private FlashcardMapper flashcardMapper;
    @Autowired private DeckMapper      deckMapper;
    @Autowired private FsrsMemoryService fsrsMemoryService;

    private final ObjectMapper mapper = new ObjectMapper();
    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(30))
            .build();

    // ─────────────────────────────────────────────
    //  文件 → 纯文本
    // ─────────────────────────────────────────────

    public String extractText(MultipartFile file) throws Exception {
        String name = Objects.requireNonNull(file.getOriginalFilename()).toLowerCase();
        if (name.endsWith(".pdf")) {
            return extractPdf(file);
        } else if (name.endsWith(".docx")) {
            return extractDocx(file);
        } else if (name.endsWith(".pptx")) {
            return extractPptx(file);
        } else {
            // txt / md / 代码文件等
            return new String(file.getBytes(), StandardCharsets.UTF_8);
        }
    }

    private String extractPdf(MultipartFile file) throws Exception {
        // PDFBox 3.x uses Loader.loadPDF() instead of PDDocument.load()
        try (PDDocument doc = Loader.loadPDF(file.getBytes())) {
            PDFTextStripper stripper = new PDFTextStripper();
            return stripper.getText(doc);
        }
    }

    private String extractDocx(MultipartFile file) throws Exception {
        try (XWPFDocument doc = new XWPFDocument(file.getInputStream())) {
            StringBuilder sb = new StringBuilder();
            for (XWPFParagraph para : doc.getParagraphs()) {
                sb.append(para.getText()).append("\n");
            }
            return sb.toString();
        }
    }

    private String extractPptx(MultipartFile file) throws Exception {
        try (XMLSlideShow ppt = new XMLSlideShow(file.getInputStream())) {
            StringBuilder sb = new StringBuilder();
            for (XSLFSlide slide : ppt.getSlides()) {
                sb.append("--- 幻灯片 ---\n");
                for (XSLFShape shape : slide.getShapes()) {
                    if (shape instanceof XSLFTextShape ts) {
                        sb.append(ts.getText()).append("\n");
                    }
                }
            }
            return sb.toString();
        }
    }

    // ─────────────────────────────────────────────
    //  调用 DeepSeek 生成结构化卡组 JSON
    // ─────────────────────────────────────────────

    /**
     * @param text      从文件提取的纯文本
     * @param deckTitle 用户给卡组起的名字
     * @param customKey 用户自己的 API Key，为空则用系统 Key
     * @return 完整的层级卡组 JSON 字符串（由 AI 生成）
     */
    public String generateDeckJson(String text, String deckTitle, String customKey,
                                   int cardCount, String detailHint) throws Exception {
        String key = (customKey != null && !customKey.isBlank()) ? customKey : systemKey;
        if (key == null || key.isBlank()) {
            throw new IllegalStateException("未配置 AI API Key，请在设置中填入您的 DeepSeek Key");
        }

        // 限制输入长度，避免 token 过多（约 6000 汉字）
        if (text.length() > 12000) {
            text = text.substring(0, 12000) + "\n...（内容已截断）";
        }

        String prompt = buildPrompt(deckTitle, text, cardCount, detailHint);
        String requestBody = buildRequestBody(prompt);

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(apiUrl))
                .header("Content-Type", "application/json")
                .header("Authorization", "Bearer " + key)
                .timeout(Duration.ofSeconds(120))
                .POST(HttpRequest.BodyPublishers.ofString(requestBody, StandardCharsets.UTF_8))
                .build();

        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
        log.info("DeepSeek response status: {}", response.statusCode());

        if (response.statusCode() != 200) {
            log.error("DeepSeek error: {}", response.body());
            throw new RuntimeException("AI 服务调用失败：" + response.statusCode());
        }

        // 解析 OpenAI 格式响应，取出 content
        JsonNode root = mapper.readTree(response.body());
        String content = root.path("choices").get(0)
                .path("message").path("content").asText();

        // AI 有时会在 JSON 外加 markdown 代码块，去掉
        content = content.trim();
        if (content.startsWith("```")) {
            content = content.replaceFirst("```[a-z]*\\n?", "").replaceAll("```$", "").trim();
        }

        return content;
    }

    private String buildPrompt(String deckTitle, String text, int cardCount, String detailHint) {
        String countInstruction = cardCount <= 0
            ? "根据内容的信息量自行决定生成卡片总数，确保覆盖所有重要知识点，不要人为限制张数"
            : "总共生成约 " + cardCount + " 张闪卡，各子卡组的卡片数量按内容比重自然分配";

        return """
                你是一个专业的学习辅助 AI。请根据下面的学习材料，生成一份结构化的闪卡卡组，用于间隔复习。

                要求：
                1. 顶层卡组名称为：%s
                2. 根据内容的知识主题自由划分子卡组，子卡组名称要体现知识模块（例如考研数学可分为"高等数学""线性代数""概率论"，Java 可分为"集合框架""并发""JVM"等）
                3. 子卡组数量由内容决定，不做硬性限制，做到每个子卡组主题清晰、不重叠
                4. %s
                5. 问题要清晰，每题考察一个独立知识点
                6. 答案要求：%s
                7. 严格返回如下 JSON 格式，不要加任何解释或代码块标记：

                {
                  "title": "顶层卡组名称",
                  "category": "学科分类（如 Java/计算机网络/数学等）",
                  "description": "一句话描述这份资料的核心内容",
                  "children": [
                    {
                      "title": "子卡组名称（体现知识主题）",
                      "cards": [
                        { "question": "问题1", "answer": "答案1" },
                        { "question": "问题2", "answer": "答案2" }
                      ]
                    }
                  ]
                }

                学习材料：
                %s
                """.formatted(deckTitle, countInstruction, detailHint, text);
    }

    private String buildRequestBody(String prompt) throws Exception {
        Map<String, Object> message = Map.of("role", "user", "content", prompt);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("model", defaultModel);
        body.put("messages", List.of(message));
        body.put("temperature", 0.3);
        body.put("max_tokens", 8192);
        return mapper.writeValueAsString(body);
    }

    /** 通用 AI 调用，返回 content 字符串（已去 markdown 代码块） */
    private String callAI(String prompt, String key) throws Exception {
        String requestBody = buildRequestBody(prompt);
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(apiUrl))
                .header("Content-Type", "application/json")
                .header("Authorization", "Bearer " + key)
                .timeout(Duration.ofSeconds(120))
                .POST(HttpRequest.BodyPublishers.ofString(requestBody, StandardCharsets.UTF_8))
                .build();
        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() != 200) throw new RuntimeException("AI 调用失败: " + response.statusCode());
        String content = mapper.readTree(response.body())
                .path("choices").get(0).path("message").path("content").asText();
        content = content.trim();
        if (content.startsWith("```")) {
            content = content.replaceFirst("```[a-z]*\\n?", "").replaceAll("```\\s*$", "").trim();
        }
        return content;
    }

    // ─────────────────────────────────────────────
    //  知识图谱生成
    // ─────────────────────────────────────────────

    public KnowledgeGraphVO generateKnowledgeGraph(String customKey) throws Exception {
        String key = (customKey != null && !customKey.isBlank()) ? customKey : systemKey;
        if (key == null || key.isBlank()) throw new IllegalStateException("未配置 AI API Key");

        List<Flashcard> all = flashcardMapper.selectList(null);
        KnowledgeGraphVO empty = new KnowledgeGraphVO();
        empty.setNodes(List.of()); empty.setEdges(List.of());
        if (all.isEmpty()) return empty;

        // 最多取 50 张，避免 token 爆炸
        List<Flashcard> sample = all.size() > 50 ? all.subList(0, 50) : all;

        // 构建 deckId → deck 映射 & cardId → card 映射
        Map<Long, Deck> deckMap = deckMapper.selectList(null).stream()
                .collect(Collectors.toMap(Deck::getId, d -> d));
        Map<Long, Flashcard> cardMap = sample.stream()
                .collect(Collectors.toMap(Flashcard::getId, c -> c));

        // 拼卡片列表给 AI
        StringBuilder sb = new StringBuilder();
        for (Flashcard c : sample) {
            Deck d = deckMap.get(c.getDeckId());
            String dTitle = d != null ? d.getTitle() : "未知卡组";
            long   dId    = d != null ? d.getId()    : 0;
            sb.append(String.format("%d|%d|%s|%s\n", c.getId(), dId, dTitle, c.getQuestion()));
        }

        String content = callAI(buildGraphPrompt(sb.toString()), key);

        // 解析
        JsonNode root = mapper.readTree(content);
        List<KnowledgeGraphVO.NodeVO> nodes = new ArrayList<>();
        for (JsonNode n : root.path("nodes")) {
            KnowledgeGraphVO.NodeVO node = new KnowledgeGraphVO.NodeVO();
            node.setId(n.path("id").asText());
            node.setLabel(n.path("label").asText());
            node.setDeckId(n.path("deckId").asInt());
            node.setDeckTitle(n.path("deckTitle").asText());
            node.setCore(n.path("isCore").asBoolean(false));
            // 填入真实复习数据
            try {
                long cardId = Long.parseLong(n.path("id").asText());
                Flashcard card = cardMap.get(cardId);
                if (card != null) {
                    node.setMemoryScore(fsrsMemoryService.currentScore(card, java.time.LocalDateTime.now()));
                    node.setReviewCount(card.getReviewCount() != null ? card.getReviewCount() : 0);
                }
            } catch (NumberFormatException ignored) {}
            nodes.add(node);
        }
        List<KnowledgeGraphVO.EdgeVO> edges = new ArrayList<>();
        for (JsonNode e : root.path("edges")) {
            KnowledgeGraphVO.EdgeVO edge = new KnowledgeGraphVO.EdgeVO();
            edge.setSource(e.path("source").asText());
            edge.setTarget(e.path("target").asText());
            edge.setLabel(e.path("label").asText(""));
            edges.add(edge);
        }
        KnowledgeGraphVO vo = new KnowledgeGraphVO();
        vo.setNodes(nodes); vo.setEdges(edges);
        return vo;
    }

    private String buildGraphPrompt(String cardList) {
        return """
                你是知识图谱分析专家。请分析以下学习卡片，找出知识关联，构建图谱。

                卡片列表（格式：卡片ID|卡组ID|卡组名|问题）：
                %s

                要求：
                1. 找出有实质关联的卡片对（前置知识、同族概念、对比关系、因果关系等）
                2. 宁缺毋滥，不要强行关联无关内容
                3. 被三张以上卡片关联的核心节点 isCore 设为 true
                4. 关系描述不超过 8 个字
                5. nodes 只包含参与了关联的卡片（没有边的孤立节点不用列出）
                6. 严格返回 JSON，不加代码块或任何解释：

                {
                  "nodes": [{"id":"1","label":"问题摘要≤12字","deckId":1,"deckTitle":"卡组名","isCore":false}],
                  "edges": [{"source":"1","target":"2","label":"关系描述"}]
                }
                """.formatted(cardList);
    }
}
