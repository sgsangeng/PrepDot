package com.prepdot.common;

/**
 * 当前请求的用户上下文（基于 ThreadLocal）
 *
 * Tomcat 是「一请求一线程」模型，所以 ThreadLocal 天然就是请求级作用域，
 * 避免把 userId 作为参数在 Controller → Service → Mapper 层层透传。
 */
public final class UserContext {

    private static final ThreadLocal<Long> CURRENT_USER_ID = new ThreadLocal<>();

    private UserContext() {}   // 工具类，禁止实例化

    public static void set(Long userId) {
        CURRENT_USER_ID.set(userId);
    }

    /**
     * 获取当前用户 id。
     * 经过 JwtAuthFilter 的接口保证非空；取不到说明该接口漏配了鉴权。
     */
    public static Long getUserId() {
        Long userId = CURRENT_USER_ID.get();
        if (userId == null) {
            throw BusinessException.unauthorized("未获取到登录用户");
        }
        return userId;
    }

    /** 允许为空的版本：白名单接口里可能确实没有用户 */
    public static Long getUserIdOrNull() {
        return CURRENT_USER_ID.get();
    }

    public static void clear() {
        CURRENT_USER_ID.remove();
    }
}