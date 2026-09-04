package com.prepdot.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.prepdot.common.BusinessException;
import com.prepdot.entity.AgentRun;
import com.prepdot.entity.DailyPlan;
import com.prepdot.entity.Deck;
import com.prepdot.entity.ReviewRecord;
import com.prepdot.entity.User;
import com.prepdot.mapper.AgentRunMapper;
import com.prepdot.mapper.DailyPlanMapper;
import com.prepdot.mapper.DeckMapper;
import com.prepdot.mapper.ReviewRecordMapper;
import com.prepdot.mapper.UserMapper;
import com.prepdot.service.AccountService;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
public class AccountServiceImpl implements AccountService {

    private static final BCryptPasswordEncoder PASSWORD_ENCODER = new BCryptPasswordEncoder();

    private final UserMapper userMapper;
    private final ReviewRecordMapper reviewRecordMapper;
    private final DailyPlanMapper dailyPlanMapper;
    private final AgentRunMapper agentRunMapper;
    private final DeckMapper deckMapper;

    @Override
    @Transactional
    public void deleteAccount(Long userId, String password) {
        User user = userMapper.selectById(userId);
        if (user == null) {
            throw BusinessException.notFound("用户不存在");
        }
        if (!PASSWORD_ENCODER.matches(password, user.getPassword())) {
            throw BusinessException.badRequest("密码错误");
        }

        // 先删除直接按用户归属的数据；数据库外键会级联删除计划项和 Agent 步骤。
        reviewRecordMapper.delete(new LambdaQueryWrapper<ReviewRecord>()
                .eq(ReviewRecord::getUserId, userId));
        dailyPlanMapper.delete(new LambdaQueryWrapper<DailyPlan>()
                .eq(DailyPlan::getUserId, userId));
        agentRunMapper.delete(new LambdaQueryWrapper<AgentRun>()
                .eq(AgentRun::getUserId, userId));

        List<Long> ownedDeckIds = deckMapper.selectList(new LambdaQueryWrapper<Deck>()
                        .eq(Deck::getUserId, userId))
                .stream().map(Deck::getId).toList();
        if (!ownedDeckIds.isEmpty()) {
            // 防御历史脏数据：先断开其他用户/公共卡组对待删除卡组的父子引用。
            deckMapper.detachForeignChildren(ownedDeckIds, userId);
            // 删除卡组后，卡片、剩余复习记录和计划项由外键级联删除。
            deckMapper.delete(new LambdaQueryWrapper<Deck>()
                    .eq(Deck::getUserId, userId));
        }

        userMapper.deleteById(userId);
    }
}
