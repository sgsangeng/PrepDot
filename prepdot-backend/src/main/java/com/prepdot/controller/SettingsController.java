package com.prepdot.controller;

import com.prepdot.common.Result;
import com.prepdot.service.SettingsService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@Tag(name = "应用设置")
@RestController
@RequestMapping("/api/settings")
@RequiredArgsConstructor
public class SettingsController {

    private final SettingsService settingsService;

    @Operation(summary = "获取所有设置项（key-value 形式）")
    @GetMapping
    public Result<Map<String, String>> getAll() {
        return Result.success(settingsService.getAll());
    }

    @Operation(summary = "批量保存设置项（传入 key-value map，新增或更新）")
    @PutMapping
    public Result<Void> saveAll(@RequestBody Map<String, String> settings) {
        settingsService.saveAll(settings);
        return Result.success();
    }
}
