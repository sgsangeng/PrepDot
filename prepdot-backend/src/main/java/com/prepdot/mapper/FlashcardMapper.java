package com.prepdot.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.prepdot.entity.Flashcard;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.util.List;

@Mapper
public interface FlashcardMapper extends BaseMapper<Flashcard> {

    /**
     * 查询今日到期需复习的卡片（nextReviewAt <= now），按记忆度升序
     */
    List<Flashcard> selectDueCards(@Param("limit") int limit, @Param("userId") Long userId);
}
