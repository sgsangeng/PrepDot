package com.prepdot.dto.request;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

import java.util.List;

@Data
public class DeckRequest {

    @NotBlank(message = "卡组名称不能为空")
    private String title;

    private String type = "导入卡包";

    private String category = "综合";

    private String description;

    /** 批量导入时携带的卡片列表（可选） */
    private List<CardRequest> cards;
}
