package com.prepdot.controller;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.prepdot.common.Result;
import com.prepdot.common.UserContext;
import com.prepdot.dto.request.DeckRequest;
import com.prepdot.dto.response.CommunityPackVO;
import com.prepdot.dto.response.DeckVO;
import com.prepdot.service.DeckService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.core.io.ClassPathResource;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.util.List;

@Tag(name = "精选卡包社区")
@RestController
@RequestMapping("/api/community")
@RequiredArgsConstructor
public class CommunityController {

    private final DeckService deckService;
    private final ObjectMapper objectMapper;

    /** 获取所有精选卡包（不含卡片内容，只展示元信息） */
    @Operation(summary = "获取精选卡包列表")
    @GetMapping("/packs")
    public Result<List<CommunityPackVO>> listPacks() throws IOException {
        List<CommunityPackVO> packs = loadPacks();
        // 返回列表时不带 cards 内容，节省流量
        packs.forEach(p -> p.setCards(null));
        return Result.success(packs);
    }

    /** 获取单个卡包详情（含所有卡片） */
    @Operation(summary = "获取卡包详情（含卡片）")
    @GetMapping("/packs/{id}")
    public Result<CommunityPackVO> getPack(@PathVariable Integer id) throws IOException {
        return loadPacks().stream()
                .filter(p -> p.getId().equals(id))
                .findFirst()
                .map(Result::success)
                .orElse(Result.error(404, "卡包不存在"));
    }

    /** 一键将精选卡包导入到我的卡组 */
    @Operation(summary = "一键导入卡包到我的卡组")
    @PostMapping("/packs/{id}/import")
    public Result<DeckVO> importPack(@PathVariable Integer id) throws IOException {
        CommunityPackVO pack = loadPacks().stream()
                .filter(p -> p.getId().equals(id))
                .findFirst()
                .orElseThrow(() -> new RuntimeException("卡包不存在: " + id));

        DeckRequest request = new DeckRequest();
        request.setTitle(pack.getTitle());
        request.setCategory(pack.getCategory());
        request.setDescription(pack.getDescription());
        request.setType("精选卡包");
        request.setCards(pack.getCards());

        return Result.success(deckService.create(request, UserContext.getUserId()));
    }

    // ---- 私有：读取 JSON 文件 ----
    private List<CommunityPackVO> loadPacks() throws IOException {
        var resource = new ClassPathResource("community-packs.json");
        return objectMapper.readValue(
                resource.getInputStream(),
                new TypeReference<>() {}
        );
    }
}
