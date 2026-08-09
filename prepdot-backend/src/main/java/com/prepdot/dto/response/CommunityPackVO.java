package com.prepdot.dto.response;

import com.prepdot.dto.request.CardRequest;
import lombok.Data;

import java.util.List;

@Data
public class CommunityPackVO {
    private Integer id;
    private String title;
    private String category;
    private String description;
    private Integer cardCount;
    private List<String> tags;
    private List<CardRequest> cards;
}
