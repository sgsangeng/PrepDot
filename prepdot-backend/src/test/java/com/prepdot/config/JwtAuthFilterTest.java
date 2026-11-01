package com.prepdot.config;

import com.prepdot.mapper.UserMapper;
import com.prepdot.util.JwtUtil;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.util.concurrent.atomic.AtomicBoolean;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.mock;

class JwtAuthFilterTest {

    private JwtAuthFilter filter() {
        return new JwtAuthFilter(mock(JwtUtil.class), mock(UserMapper.class));
    }

    @Test
    void optionsPreflightPassesWithoutToken() throws Exception {
        MockHttpServletRequest req = new MockHttpServletRequest("OPTIONS", "/api/plan/review");
        MockHttpServletResponse resp = new MockHttpServletResponse();
        AtomicBoolean passed = new AtomicBoolean(false);

        filter().doFilter(req, resp, (request, response) -> passed.set(true));

        assertTrue(passed.get(), "预检应放行到后续 CORS 处理");
        assertEquals(200, resp.getStatus());
    }

    @Test
    void getWithoutTokenStillReturns401() throws Exception {
        MockHttpServletRequest req = new MockHttpServletRequest("GET", "/api/decks");
        MockHttpServletResponse resp = new MockHttpServletResponse();
        AtomicBoolean passed = new AtomicBoolean(false);

        filter().doFilter(req, resp, (request, response) -> passed.set(true));

        assertFalse(passed.get());
        assertEquals(401, resp.getStatus());
    }
}
