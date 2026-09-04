package com.prepdot.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.prepdot.entity.Deck;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Update;

import java.util.List;

@Mapper
public interface DeckMapper extends BaseMapper<Deck> {

    @Update("""
        <script>
        UPDATE deck
        SET parent_id = NULL
        WHERE parent_id IN
        <foreach collection="parentIds" item="id" open="(" separator="," close=")">
            #{id}
        </foreach>
        AND (user_id != #{userId} OR user_id IS NULL)
        </script>
        """)
    int detachForeignChildren(@Param("parentIds") List<Long> parentIds,
                              @Param("userId") Long userId);
}
