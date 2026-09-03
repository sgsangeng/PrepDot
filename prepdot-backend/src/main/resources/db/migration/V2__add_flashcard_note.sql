ALTER TABLE flashcard
    ADD COLUMN note TEXT NULL COMMENT '复习笔记（用户自加，不影响原始内容）'
    AFTER stability;
