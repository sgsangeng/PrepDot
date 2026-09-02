package com.prepdot.dto.request;

import lombok.Data;

@Data
public class NoteRequest {

    /** 笔记内容；传空字符串表示清除笔记 */
    private String note;
}
