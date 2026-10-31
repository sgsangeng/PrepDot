-- 演示账号 demo 的回填脚本：在 reset-demo.sh 重新导入 3 个卡组之后执行。
--
-- 说明：
-- 1. 三个队列通过 flashcard.id % 10 划分，依赖自增 id 的分布，因此 18 / 24 / 18
--    只是近似值（导入期间若有其他用户写入卡片，id 可能不连续）。
-- 2. review_record 只为「已复习」的卡片生成（difficulty IS NOT NULL，即前两批），
--    「从未复习」的第三批保持 next_review_at 为未来时间，避免今日队列过大。
-- 3. flashcard.next_review_at 为 NOT NULL，因此第三批也必须显式设置未来时间。
-- 4. V4 迁移已删除 flashcard.memory_score 列，本脚本不再写该字段；
--    review_record 的 memory_score_before/after 仍保留。

SET @demo_id = (SELECT id FROM user WHERE username = 'demo');

-- 18 张：已复习且今天到期（next_review_at 在过去或当前时刻）
UPDATE flashcard f JOIN deck d ON f.deck_id = d.id
SET f.difficulty = 3 + (f.id % 5),
    f.stability = 0.8 + (f.id % 7),
    f.review_count = 1 + (f.id % 4),
    f.last_reviewed_at = NOW() - INTERVAL (1 + f.id % 10) DAY,
    f.next_review_at = NOW() - INTERVAL (f.id % 3) HOUR
WHERE d.user_id = @demo_id AND f.id % 10 IN (0, 1, 2);

-- 24 张：已复习且未来到期
UPDATE flashcard f JOIN deck d ON f.deck_id = d.id
SET f.difficulty = 4 + (f.id % 6),
    f.stability = 2 + (f.id % 20),
    f.review_count = 2 + (f.id % 6),
    f.last_reviewed_at = NOW() - INTERVAL (2 + f.id % 12) DAY,
    f.next_review_at = NOW() + INTERVAL (1 + f.id % 20) DAY
WHERE d.user_id = @demo_id AND f.id % 10 IN (3, 4, 5, 6);

-- 18 张：从未复习，安排到未来，避免今日队列过大
UPDATE flashcard f JOIN deck d ON f.deck_id = d.id
SET f.difficulty = NULL,
    f.stability = NULL,
    f.review_count = 0,
    f.last_reviewed_at = NULL,
    f.next_review_at = NOW() + INTERVAL (1 + f.id % 7) DAY
WHERE d.user_id = @demo_id AND f.id % 10 IN (7, 8, 9);

-- 过去 14 天的复习历史：每张已复习卡片 8 条
INSERT INTO review_record (user_id, card_id, rating, memory_score_before, memory_score_after, reviewed_at)
SELECT @demo_id,
       f.id,
       ELT(1 + ((f.id + n.n) % 4), 'again', 'hard', 'good', 'easy'),
       25 + ((f.id * 7 + n.n * 11) % 50),
       35 + ((f.id * 5 + n.n * 13) % 55),
       NOW() - INTERVAL ((f.id + n.n * 2) % 14) DAY - INTERVAL (n.n * 37) MINUTE
FROM flashcard f
JOIN deck d ON f.deck_id = d.id
JOIN (
  SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
  UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
) n
WHERE d.user_id = @demo_id AND f.difficulty IS NOT NULL;
