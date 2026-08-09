package com.prepdot.dto.response;

import lombok.Data;

@Data
public class AuthVO {
    private String token;
    private Long   userId;
    private String username;
    private String nickname;
    private String avatarColor;
    private Integer studyTarget;
}
