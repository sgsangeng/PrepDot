package com.prepdot.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.prepdot.dto.request.DeckRequest;
import com.prepdot.dto.response.DeckVO;
import com.prepdot.entity.Flashcard;

import java.util.List;

public interface DeckService {

    List<DeckVO> listAll(Long userId);

    DeckVO create(DeckRequest request, Long userId);

    /** 根据层级 JSON 树创建卡组（AI 生成或 JSON 导入） */
    DeckVO createHierarchical(JsonNode root, Long userId);

    DeckVO update(Long id, DeckRequest request);

    void delete(Long id);

    List<Flashcard> listCards(Long deckId);
}
