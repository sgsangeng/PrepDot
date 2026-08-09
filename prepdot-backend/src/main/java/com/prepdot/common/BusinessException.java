package com.prepdot.common;

import lombok.Getter;

/**
 * 业务异常基类：携带 HTTP 状态码，由 GlobalExceptionHandler 统一转换
 */
@Getter
public class BusinessException extends RuntimeException {

    private final int code;

    public BusinessException(int code, String message) {
        super(message);
        this.code = code;
    }

    /** 401 未认证：没登录 / token 无效 */
    public static BusinessException unauthorized(String message) {
        return new BusinessException(401, message);
    }

    /** 403 无权限：登录了，但这资源不是你的 */
    public static BusinessException forbidden(String message) {
        return new BusinessException(403, message);
    }

    /** 404 资源不存在 */
    public static BusinessException notFound(String message) {
        return new BusinessException(404, message);
    }

    /** 400 参数/业务规则错误 */
    public static BusinessException badRequest(String message) {
        return new BusinessException(400, message);
    }
}