-- 兼容两类已有环境：旧库可能没有 note，也可能已被原 schema.sql 创建过。
SET @note_column_exists = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'flashcard'
      AND column_name = 'note'
);

SET @add_note_sql = IF(
    @note_column_exists = 0,
    'ALTER TABLE flashcard ADD COLUMN note TEXT NULL COMMENT ''复习笔记（用户自加，不影响原始内容）'' AFTER stability',
    'SELECT 1'
);

PREPARE add_note_statement FROM @add_note_sql;
EXECUTE add_note_statement;
DEALLOCATE PREPARE add_note_statement;
