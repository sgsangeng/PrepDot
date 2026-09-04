package com.prepdot.dto.request;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class DeleteAccountRequest {

    @NotBlank(message = "请输入当前密码")
    private String password;
}
