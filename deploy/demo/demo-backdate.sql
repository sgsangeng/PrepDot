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
-- 5. 本脚本可重复执行：写历史前会先删除 demo 自己卡片上的已有复习记录，
--    单独重跑 SQL 不会产生重复历史。

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

-- 过去 14 天的复习历史：每张已复习卡片 8 条。
-- 先清掉 demo 卡片上的旧记录，保证本脚本反复执行也不会累积重复数据。
DELETE FROM review_record
WHERE user_id = @demo_id
  AND card_id IN (
    SELECT f.id FROM flashcard f JOIN deck d ON f.deck_id = d.id
    WHERE d.user_id = @demo_id
  );

-- after 由 before 派生，保证 memory_score_after 始终大于 memory_score_before。
INSERT INTO review_record (user_id, card_id, rating, memory_score_before, memory_score_after, reviewed_at)
SELECT base.user_id,
       base.card_id,
       base.rating,
       base.before_score,
       LEAST(100, base.before_score + 1 + ((base.card_id * 3 + base.n * 5) % 20)),
       base.reviewed_at
FROM (
  SELECT @demo_id AS user_id,
         f.id AS card_id,
         ELT(1 + ((f.id + n.n) % 4), 'again', 'hard', 'good', 'easy') AS rating,
         25 + ((f.id * 7 + n.n * 11) % 50) AS before_score,
         n.n AS n,
         NOW() - INTERVAL ((f.id + n.n * 2) % 14) DAY - INTERVAL (n.n * 37) MINUTE AS reviewed_at
  FROM flashcard f
  JOIN deck d ON f.deck_id = d.id
  JOIN (
    SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
    UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
  ) n
  WHERE d.user_id = @demo_id AND f.difficulty IS NOT NULL
) AS base;
