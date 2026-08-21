package com.prepdot.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.prepdot.entity.User;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;
import java.util.Map;

@Mapper
public interface UserMapper extends BaseMapper<User> {

    @Select("""
        SELECT DATE(rr.reviewed_at) AS day, COUNT(*) AS count
        FROM review_record rr
        JOIN flashcard f ON rr.card_id = f.id
        JOIN deck d ON f.deck_id = d.id
        WHERE rr.reviewed_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
          AND (#{userId} IS NULL OR d.user_id = #{userId})
        GROUP BY DATE(rr.reviewed_at)
        ORDER BY day ASC
        """)
    List<Map<String, Object>> weeklyStats(@Param("userId") Long userId);

    @Select("""
        SELECT COUNT(*)
        FROM review_record rr
        JOIN flashcard f ON rr.card_id = f.id
        JOIN deck d ON f.deck_id = d.id
        WHERE DATE(rr.reviewed_at) = CURDATE()
          AND (#{userId} IS NULL OR d.user_id = #{userId})
        """)
    int todayReviewCount(@Param("userId") Long userId);

    @Select("""
        SELECT COUNT(*)
        FROM review_record rr
        JOIN flashcard f ON rr.card_id = f.id
        JOIN deck d ON f.deck_id = d.id
        WHERE #{userId} IS NULL OR d.user_id = #{userId}
        """)
    int totalReviewCount(@Param("userId") Long userId);
}
