package com.prepdot.controller;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.prepdot.common.Result;
import com.prepdot.common.UserContext;
import com.prepdot.dto.response.AuthVO;
import com.prepdot.dto.response.UserStatsVO;
import com.prepdot.entity.User;
import com.prepdot.mapper.DeckMapper;
import com.prepdot.mapper.FlashcardMapper;
import com.prepdot.mapper.UserMapper;
import com.prepdot.util.JwtUtil;
import com.prepdot.service.FsrsMemoryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@Slf4j
@Tag(name = "用户认证")
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    private final UserMapper      userMapper;
    private final DeckMapper      deckMapper;
    private final FlashcardMapper flashcardMapper;
    private final JwtUtil         jwtUtil;
    private final FsrsMemoryService fsrsMemoryService;

    private static final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();

    // ── 请求体 ──────────────────────────────────────
    @Data static class RegisterReq {
        String username;
        String password;
        String nickname;
    }
    @Data static class LoginReq {
        String username;
        String password;
    }
    @Data static class UpdateProfileReq {
        String nickname;
        String avatarColor;
        Integer studyTarget;
    }

    // ── 注册 ──────────────────────────────────────
    @Operation(summary = "注册")
    @PostMapping("/register")
    public Result<AuthVO> register(@RequestBody RegisterReq req) {
        if (req.getUsername() == null || req.getUsername().isBlank())
            return Result.error("用户名不能为空");
        if (req.getPassword() == null || req.getPassword().length() < 6)
            return Result.error("密码至少 6 位");

        // 检查用户名是否已存在
        Long count = userMapper.selectCount(
            new LambdaQueryWrapper<User>().eq(User::getUsername, req.getUsername().trim()));
        if (count > 0) return Result.error("用户名已被占用");

        User user = new User();
        user.setUsername(req.getUsername().trim());
        user.setNickname(req.getNickname() != null && !req.getNickname().isBlank()
                         ? req.getNickname().trim() : req.getUsername().trim());
        user.setPassword(encoder.encode(req.getPassword()));
        user.setAvatarColor("#6366F1");
        user.setStudyTarget(20);
        userMapper.insert(user);

        return Result.success(buildAuthVO(user));
    }

    // ── 登录 ──────────────────────────────────────
    @Operation(summary = "登录")
    @PostMapping("/login")
    public Result<AuthVO> login(@RequestBody LoginReq req) {
        User user = userMapper.selectOne(
            new LambdaQueryWrapper<User>().eq(User::getUsername, req.getUsername()));
        if (user == null) return Result.error("用户名不存在");
        if (!encoder.matches(req.getPassword(), user.getPassword()))
            return Result.error("密码错误");
        return Result.success(buildAuthVO(user));
    }

    // ── 获取个人统计 ──────────────────────────────
    @Operation(summary = "获取学习统计数据")
    @GetMapping("/stats")
    public Result<UserStatsVO> stats() {
        Long userId = UserContext.getUserId();

        UserStatsVO vo = new UserStatsVO();
        vo.setStreakDays(calcStreak(userId));
        vo.setTodayReviewed(userMapper.todayReviewCount(userId));
        vo.setTotalReviewed(userMapper.totalReviewCount(userId));

        // 只统计当前用户的卡组和卡片
        var deckQw = new com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper<com.prepdot.entity.Deck>()
                .eq(userId != null, com.prepdot.entity.Deck::getUserId, userId);
        vo.setTotalDecks(deckMapper.selectCount(deckQw).intValue());

        // 通过用户的卡组找卡片
        var userDecks = deckMapper.selectList(deckQw);
        if (userDecks.isEmpty()) {
            vo.setTotalCards(0);
            vo.setAvgMemoryScore(0);
        } else {
            var deckIds = userDecks.stream().map(com.prepdot.entity.Deck::getId).toList();
            var cards = flashcardMapper.selectList(
                new com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper<com.prepdot.entity.Flashcard>()
                    .in(com.prepdot.entity.Flashcard::getDeckId, deckIds)
            );
            var now = java.time.LocalDateTime.now();
            var scores = cards.stream().map(c -> fsrsMemoryService.currentScore(c, now)).toList();
            vo.setTotalCards(cards.size());
            vo.setAvgMemoryScore(scores.isEmpty() ? 0 :
                    (int) scores.stream().mapToInt(Integer::intValue).average().orElse(0));
            vo.setMemoryDistribution(Map.of(
                    "low", scores.stream().filter(score -> score < 40).count(),
                    "mid", scores.stream().filter(score -> score >= 40 && score < 70).count(),
                    "high", scores.stream().filter(score -> score >= 70).count()));
        }

        vo.setWeeklyData(userMapper.weeklyStats(userId));
        if (vo.getMemoryDistribution() == null) {
            vo.setMemoryDistribution(Map.of("low", 0, "mid", 0, "high", 0));
        }
        return Result.success(vo);
    }

    // ── 更新个人信息 ──────────────────────────────
    @Operation(summary = "更新个人信息")
    @PutMapping("/profile")
    public Result<AuthVO> updateProfile(@RequestBody UpdateProfileReq req) {
        Long userId = UserContext.getUserId();

        User user = userMapper.selectById(userId);
        if (user == null) return Result.error("用户不存在");

        if (req.getNickname() != null && !req.getNickname().isBlank())
            user.setNickname(req.getNickname().trim());
        if (req.getAvatarColor() != null)
            user.setAvatarColor(req.getAvatarColor());
        if (req.getStudyTarget() != null && req.getStudyTarget() > 0)
            user.setStudyTarget(req.getStudyTarget());
        userMapper.updateById(user);
        return Result.success(buildAuthVO(user));
    }

    // ── 工具方法 ──────────────────────────────────
    private AuthVO buildAuthVO(User user) {
        AuthVO vo = new AuthVO();
        vo.setToken(jwtUtil.generate(user.getId(), user.getUsername()));
        vo.setUserId(user.getId());
        vo.setUsername(user.getUsername());
        vo.setNickname(user.getNickname());
        vo.setAvatarColor(user.getAvatarColor());
        vo.setStudyTarget(user.getStudyTarget());
        return vo;
    }

    /** 计算连续打卡天数（按用户） */
    private int calcStreak(Long userId) {
        try {
            var dates = userMapper.weeklyStats(userId).stream()
                .map(m -> m.get("day").toString()).toList();
            return userMapper.todayReviewCount(userId) > 0 ? Math.max(1, dates.size()) : 0;
        } catch (Exception e) {
            return 0;
        }
    }
}
