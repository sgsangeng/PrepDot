package com.prepdot.service;

import com.prepdot.dto.request.CardRequest;
import com.prepdot.entity.Flashcard;

import java.util.List;

public interface CardService {

    /** 新建卡片：会校验 request.deckId 是否属于 userId */
    Flashcard create(CardRequest request, Long userId);

    /** 更新卡片：会校验该卡片所在卡组是否属于 userId */
    Flashcard update(Long id, CardRequest request, Long userId);

    /** 删除卡片：会校验该卡片所在卡组是否属于 userId */
    void delete(Long id, Long userId);

    /** 批量删除：只会删除属于 userId 的那部分，其余静默忽略 */
    void deleteBatch(List<Long> ids, Long userId);
}
