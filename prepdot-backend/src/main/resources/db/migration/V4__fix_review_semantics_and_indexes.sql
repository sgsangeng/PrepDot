-- memory_score 存储列下线：掌握度由 FSRS 实时计算，存储值评分后恒写 100，
-- 导致到期队列"弱卡优先"排序失效，且与新卡 fallback 语义冲突
ALTER TABLE flashcard DROP COLUMN memory_score;

-- 核心查询列补索引：到期卡片、统计与注销清理此前均走全表扫描
CREATE INDEX idx_deck_user ON deck(user_id);
CREATE INDEX idx_flashcard_next_review ON flashcard(next_review_at);
CREATE INDEX idx_review_record_reviewed_at ON review_record(reviewed_at);
CREATE INDEX idx_review_record_user ON review_record(user_id);

-- 并发补题可能为同一计划插入重复卡片，先清理历史重复再加唯一约束
DELETE i1 FROM daily_plan_item i1
JOIN daily_plan_item i2
  ON i1.plan_id = i2.plan_id AND i1.card_id = i2.card_id AND i1.id > i2.id;
ALTER TABLE daily_plan_item ADD CONSTRAINT uk_item_plan_card UNIQUE (plan_id, card_id);
