package com.prepdot.controller;

import com.prepdot.common.BusinessException;
import com.prepdot.common.Result;
import com.prepdot.common.UserContext;
import com.prepdot.dto.request.DeckRequest;
import com.prepdot.dto.response.DeckVO;
import com.prepdot.entity.Deck;
import com.prepdot.entity.Flashcard;
import com.prepdot.mapper.DeckMapper;
import com.prepdot.service.DeckService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Tag(name = "卡组管理")
@RestController
@RequestMapping("/api/decks")
@RequiredArgsConstructor
public class DeckController {

    private final DeckService deckService;
    private final DeckMapper  deckMapper;

    /** 校验卡组归属，不属于当前用户则抛异常（userId==null 的老数据视为公共数据，放行） */
    private void checkOwner(Long deckId, Long userId) {
        Deck deck = deckMapper.selectById(deckId);
        if (deck == null) throw BusinessException.notFound("卡组不存在");
        if (deck.getUserId() != null && !deck.getUserId().equals(userId)) {
            throw BusinessException.forbidden("无权操作该卡组");
        }
    }

    @Operation(summary = "获取当前用户的所有卡组")
    @GetMapping
    public Result<List<DeckVO>> listAll() {
        return Result.success(deckService.listAll(UserContext.getUserId()));
    }

    @Operation(summary = "新建卡组")
    @PostMapping
    public Result<DeckVO> create(@Valid @RequestBody DeckRequest request) {
        return Result.success(deckService.create(request, UserContext.getUserId()));
    }

    @Operation(summary = "编辑卡组")
    @PutMapping("/{id}")
    public Result<DeckVO> update(@PathVariable Long id, @RequestBody DeckRequest request) {
        checkOwner(id, UserContext.getUserId());
        return Result.success(deckService.update(id, request));
    }

    @Operation(summary = "删除卡组")
    @DeleteMapping("/{id}")
    public Result<Void> delete(@PathVariable Long id) {
        checkOwner(id, UserContext.getUserId());
        deckService.delete(id);
        return Result.success();
    }

    @Operation(summary = "获取卡组内的所有卡片")
    @GetMapping("/{id}/cards")
    public Result<List<Flashcard>> listCards(@PathVariable Long id) {
        checkOwner(id, UserContext.getUserId());
        return Result.success(deckService.listCards(id));
    }
}
