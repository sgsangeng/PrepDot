package com.prepdot.dto.request;

import lombok.Data;

@Data
public class DeckMoveRequest {
    /** 目标父节点；为空表示移动到根级 */
    private Long parentId;
}
