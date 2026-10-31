package com.prepdot.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.prepdot.common.Result;
import com.prepdot.common.UserContext;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import com.prepdot.util.JwtUtil;
import lombok.RequiredArgsConstructor;

import java.io.IOException;
import java.util.List;

@Component
@RequiredArgsConstructor
public class JwtAuthFilter extends HttpFilter {

    //领取工具
    private final JwtUtil jwtUtil;
    private final com.prepdot.mapper.UserMapper userMapper;
    private final ObjectMapper objectMapper = new ObjectMapper();   // 新加的字段


    /** 不用查证就能进的路径 */
    private static final List<String> WHITELIST = List.of(
            "/api/health",
            "/api/auth/login",
            "/api/auth/register"
    );

    private boolean isWhitelisted(String uri) {
        return WHITELIST.stream().anyMatch(uri::startsWith);
    }

    private void writeUnauthorized(HttpServletResponse resp, String message) throws IOException {
        resp.setStatus(HttpServletResponse.SC_UNAUTHORIZED);           // 第①件事：设置状态码
        resp.setContentType("application/json;charset=UTF-8");          // 第②件事：告诉对方这是 JSON
        resp.getWriter().write(objectMapper.writeValueAsString(         // 第③件事：把对象转成 JSON 文字并写出去
                Result.error(401, message)
        ));
    }

    @Override
    protected void doFilter(HttpServletRequest req, HttpServletResponse resp, FilterChain chain)
            throws IOException, ServletException {

        String uri = req.getRequestURI();

        // 浏览器 CORS 预检不携带 Authorization；预检只做跨域协商，不执行业务。
        if ("OPTIONS".equalsIgnoreCase(req.getMethod())) {
            chain.doFilter(req, resp);
            return;
        }

        if (isWhitelisted(uri)) {
            chain.doFilter(req, resp);
            return;
        }

        // 查证
        // 1. 提取header
        String authHeader = req.getHeader("Authorization");
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            // 没带证件，或者格式不对，直接拦下
            writeUnauthorized(resp, "缺少登录凭证");
            return;
        }
        // 2. 去掉bearer标签，只留证件本身
        String token = authHeader.substring(7);
        // 3. 验证token真伪
        Long userId = jwtUtil.getUserId(token);
        if (userId == null) {
            // 证件是假的/过期
            writeUnauthorized(resp, "登录凭证无效或已过期");
            return;
        }
        // 4. 账号注销后旧 token 签名仍有效，必须确认用户仍然存在，否则会产生幽灵数据
        if (userMapper.selectById(userId) == null) {
            writeUnauthorized(resp, "账号已注销或不存在");
            return;
        }

        try {
            UserContext.set(userId);
            chain.doFilter(req, resp);
        } finally {
            UserContext.clear(); // 不管后面顺利还是出错，用完都把纸条撕掉
        }
    }
}
