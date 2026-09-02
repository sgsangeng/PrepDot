package com.prepdot.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.prepdot.entity.ReviewRecord;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;
import java.util.Map;

@Mapper
public interface ReviewRecordMapper extends BaseMapper<ReviewRecord> {

    /**
     * 统计当前用户今天复习过的卡片（按去重后的卡片），按卡组分组。
     */
    @Select("""
        SELECT d.id AS deckId, d.title AS deckTitle, COUNT(DISTINCT rr.card_id) AS reviewCount
        FROM review_record rr
        JOIN flashcard f ON rr.card_id = f.id
        JOIN deck d ON f.deck_id = d.id
        WHERE rr.reviewed_at >= CURDATE()
          AND (#{userId} IS NULL OR d.user_id = #{userId})
        GROUP BY d.id, d.title
        ORDER BY reviewCount DESC, d.id ASC
        """)
    List<Map<String, Object>> todayReviewByDeck(@Param("userId") Long userId);
}
