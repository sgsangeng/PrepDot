package com.prepdot.controller;

import com.prepdot.common.Result;
import com.prepdot.common.UserContext;
import com.prepdot.dto.request.CardRequest;
import com.prepdot.entity.Flashcard;
import com.prepdot.service.CardService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Tag(name = "卡片管理")
@RestController
@RequestMapping("/api/cards")
@RequiredArgsConstructor
public class CardController {

    private final CardService cardService;

    @Operation(summary = "新建单张卡片")
    @PostMapping
    public Result<Flashcard> create(@Valid @RequestBody CardRequest request) {
        return Result.success(cardService.create(request, UserContext.getUserId()));
    }

    @Operation(summary = "更新卡片（question/answer/category）")
    @PutMapping("/{id}")
    public Result<Flashcard> update(@PathVariable Long id,
                                    @Valid @RequestBody CardRequest request) {
        return Result.success(cardService.update(id, request, UserContext.getUserId()));
    }

    @Operation(summary = "删除卡片")
    @DeleteMapping("/{id}")
    public Result<Void> delete(@PathVariable Long id) {
        cardService.delete(id, UserContext.getUserId());
        return Result.success();
    }

    @Operation(summary = "批量删除卡片")
    @DeleteMapping("/batch")
    public Result<Void> deleteBatch(@RequestParam List<Long> ids) {
        cardService.deleteBatch(ids, UserContext.getUserId());
        return Result.success();
    }
}
