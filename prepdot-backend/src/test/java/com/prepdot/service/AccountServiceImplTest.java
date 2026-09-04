package com.prepdot.service;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.prepdot.common.BusinessException;
import com.prepdot.entity.Deck;
import com.prepdot.entity.User;
import com.prepdot.mapper.AgentRunMapper;
import com.prepdot.mapper.DailyPlanMapper;
import com.prepdot.mapper.DeckMapper;
import com.prepdot.mapper.ReviewRecordMapper;
import com.prepdot.mapper.UserMapper;
import com.prepdot.service.impl.AccountServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

class AccountServiceImplTest {

    private final UserMapper userMapper = mock(UserMapper.class);
    private final ReviewRecordMapper reviewRecordMapper = mock(ReviewRecordMapper.class);
    private final DailyPlanMapper dailyPlanMapper = mock(DailyPlanMapper.class);
    private final AgentRunMapper agentRunMapper = mock(AgentRunMapper.class);
    private final DeckMapper deckMapper = mock(DeckMapper.class);
    private AccountServiceImpl service;

    @BeforeEach
    void setUp() {
        service = new AccountServiceImpl(userMapper, reviewRecordMapper, dailyPlanMapper,
                agentRunMapper, deckMapper);
    }

    @Test
    void correctPasswordDeletesAccountAndOwnedData() {
        User user = userWithPassword("secret123");
        Deck deck = new Deck();
        deck.setId(20L);
        when(userMapper.selectById(7L)).thenReturn(user);
        when(deckMapper.selectList(any(Wrapper.class))).thenReturn(List.of(deck));

        service.deleteAccount(7L, "secret123");

        verify(reviewRecordMapper).delete(any(Wrapper.class));
        verify(dailyPlanMapper).delete(any(Wrapper.class));
        verify(agentRunMapper).delete(any(Wrapper.class));
        verify(deckMapper).detachForeignChildren(List.of(20L), 7L);
        verify(deckMapper).delete(any(Wrapper.class));
        verify(userMapper).deleteById(7L);
    }

    @Test
    void wrongPasswordKeepsAllData() {
        when(userMapper.selectById(7L)).thenReturn(userWithPassword("secret123"));

        BusinessException error = assertThrows(BusinessException.class,
                () -> service.deleteAccount(7L, "wrong-password"));

        assertEquals(400, error.getCode());
        verify(reviewRecordMapper, never()).delete(any(Wrapper.class));
        verify(userMapper).selectById(7L);
        verifyNoMoreInteractions(userMapper);
    }

    private User userWithPassword(String password) {
        User user = new User();
        user.setId(7L);
        user.setPassword(new BCryptPasswordEncoder().encode(password));
        return user;
    }
}
