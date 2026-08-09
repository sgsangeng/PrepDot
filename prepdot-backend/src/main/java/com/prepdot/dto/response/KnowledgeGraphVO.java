package com.prepdot.dto.response;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;
import java.util.List;

@Data
public class KnowledgeGraphVO {

    private List<NodeVO> nodes;
    private List<EdgeVO> edges;

    @Data
    public static class NodeVO {
        private String  id;
        private String  label;
        private int     deckId;
        private String  deckTitle;
        /** 是否核心节点（关联数多）*/
        @JsonProperty("isCore")
        private boolean isCore;
        /** 平均记忆度 0-100，用于颜色深浅 */
        private int memoryScore;
        /** 复习次数，用于节点大小 */
        private int reviewCount;
    }

    @Data
    public static class EdgeVO {
        private String source;
        private String target;
        private String label;
    }
}
