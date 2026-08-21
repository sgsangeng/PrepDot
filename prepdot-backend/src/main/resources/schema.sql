-- PrepDot 数据库初始化脚本
-- 执行前确保 MySQL 已运行，然后在终端执行：
-- mysql -u root -p < schema.sql

CREATE DATABASE IF NOT EXISTS prepdot
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE prepdot;

-- ===================== 用户表 =====================
CREATE TABLE IF NOT EXISTS user (
    id           BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    username     VARCHAR(50)  NOT NULL UNIQUE  COMMENT '登录用户名',
    nickname     VARCHAR(50)  NOT NULL DEFAULT '' COMMENT '显示昵称',
    password     VARCHAR(100) NOT NULL          COMMENT 'BCrypt 哈希密码',
    avatar_color VARCHAR(20)  NOT NULL DEFAULT '#6366F1' COMMENT '头像背景色',
    study_target INT          NOT NULL DEFAULT 20 COMMENT '每日目标卡片数',
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ===================== 卡组表 =====================
CREATE TABLE IF NOT EXISTS deck (
    id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    parent_id   BIGINT                DEFAULT NULL   COMMENT '父卡组 ID（NULL = 根节点）',
    depth       INT          NOT NULL DEFAULT 0      COMMENT '层级深度 0/1/2',
    title       VARCHAR(100) NOT NULL COMMENT '卡组名称',
    type        VARCHAR(50)  NOT NULL DEFAULT '导入卡包' COMMENT '卡组类型',
    category    VARCHAR(50)  NOT NULL DEFAULT '综合'    COMMENT '分类标签',
    description TEXT                                   COMMENT '卡组描述',
    user_id     BIGINT                DEFAULT NULL   COMMENT '所属用户',
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_deck_parent FOREIGN KEY (parent_id) REFERENCES deck(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ===================== 闪卡表 =====================
CREATE TABLE IF NOT EXISTS flashcard (
    id               BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    deck_id          BIGINT       NOT NULL                           COMMENT '所属卡组',
    question         TEXT         NOT NULL                           COMMENT '问题/正面',
    answer           TEXT         NOT NULL                           COMMENT '答案/背面',
    card_type        VARCHAR(20)  NOT NULL DEFAULT 'qa'              COMMENT '卡片类型：qa/choice/blank',
    options          TEXT                                            COMMENT '选择题选项JSON',
    category         VARCHAR(50)  NOT NULL DEFAULT '综合'            COMMENT '分类',
    memory_score     INT          NOT NULL DEFAULT 35                COMMENT '记忆度 0-100（实时计算展示用）',
    difficulty       DOUBLE                                          COMMENT 'FSRS 难度 1-10，未复习为 NULL',
    stability        DOUBLE                                          COMMENT 'FSRS 稳定性(天)，未复习为 NULL',
    review_count     INT          NOT NULL DEFAULT 0                 COMMENT '复习次数',
    last_reviewed_at DATETIME                                        COMMENT '上次复习时间',
    next_review_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '下次复习时间',
    created_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_card_deck FOREIGN KEY (deck_id) REFERENCES deck(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ===================== 每日计划表 =====================
CREATE TABLE IF NOT EXISTS daily_plan (
    id               BIGINT   NOT NULL AUTO_INCREMENT PRIMARY KEY,
    plan_date        DATE     NOT NULL                  COMMENT '计划日期',
    user_id          BIGINT            DEFAULT NULL     COMMENT '所属用户',
    total_count      INT      NOT NULL DEFAULT 0,
    completed_count  INT      NOT NULL DEFAULT 0,
    estimated_minutes INT     NOT NULL DEFAULT 0,
    created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_plan_user_date (plan_date, user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ===================== 计划项表 =====================
CREATE TABLE IF NOT EXISTS daily_plan_item (
    id       BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
    plan_id  BIGINT      NOT NULL              COMMENT '所属计划',
    card_id  BIGINT      NOT NULL              COMMENT '对应卡片',
    status   VARCHAR(10) NOT NULL DEFAULT 'pending' COMMENT 'pending | done',
    CONSTRAINT fk_item_plan FOREIGN KEY (plan_id) REFERENCES daily_plan(id) ON DELETE CASCADE,
    CONSTRAINT fk_item_card FOREIGN KEY (card_id) REFERENCES flashcard(id)  ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ===================== 复习记录表 =====================
CREATE TABLE IF NOT EXISTS review_record (
    id                   BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id              BIGINT               DEFAULT NULL COMMENT '所属用户',
    card_id              BIGINT      NOT NULL COMMENT '对应卡片',
    rating               VARCHAR(10) NOT NULL COMMENT 'again/hard/good/easy',
    memory_score_before  INT         NOT NULL COMMENT '复习前记忆度',
    memory_score_after   INT         NOT NULL COMMENT '复习后记忆度',
    reviewed_at          DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_record_card FOREIGN KEY (card_id) REFERENCES flashcard(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ===================== Agent 执行轨迹 =====================
CREATE TABLE IF NOT EXISTS agent_run (
    id            BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id       BIGINT       NOT NULL COMMENT '发起用户',
    task_type     VARCHAR(50)  NOT NULL COMMENT '任务类型',
    input         TEXT         NOT NULL COMMENT '用户原始输入',
    output        MEDIUMTEXT            COMMENT 'Agent 最终输出',
    status        VARCHAR(20)  NOT NULL COMMENT 'RUNNING/SUCCEEDED/FAILED',
    step_count    INT          NOT NULL DEFAULT 0,
    error_message TEXT                  COMMENT '失败原因',
    started_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at   DATETIME              COMMENT '结束时间',
    INDEX idx_agent_run_user_started (user_id, started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS agent_step (
    id             BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    run_id         BIGINT       NOT NULL COMMENT '所属运行',
    step_no        INT          NOT NULL COMMENT '运行内步骤序号',
    step_type      VARCHAR(20)  NOT NULL COMMENT 'MODEL/TOOL',
    model_content  MEDIUMTEXT            COMMENT '模型思考后的可见内容',
    tool_name      VARCHAR(100)           COMMENT '工具名',
    tool_arguments TEXT                   COMMENT '工具参数 JSON',
    tool_result    MEDIUMTEXT             COMMENT '工具结果',
    duration_ms    BIGINT                 COMMENT '步骤耗时',
    created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_agent_step_run FOREIGN KEY (run_id) REFERENCES agent_run(id) ON DELETE CASCADE,
    UNIQUE KEY uk_agent_step_run_no (run_id, step_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ===================== 应用设置表 =====================
CREATE TABLE IF NOT EXISTS app_settings (
    id            BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    setting_key   VARCHAR(100) NOT NULL UNIQUE COMMENT '设置键',
    setting_value TEXT                         COMMENT '设置值',
    updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ===================== 默认设置 =====================
INSERT IGNORE INTO app_settings (setting_key, setting_value) VALUES
    ('daily_target',       '20'),
    ('theme',              'light'),
    ('ai_provider',        'system'),   -- system | custom
    ('ai_model',           'deepseek-chat'),
    ('ai_custom_key',      ''),         -- 用户自己的 API Key（空=使用系统Key）
    ('ai_daily_limit',     '10');       -- 系统AI每日免费次数
