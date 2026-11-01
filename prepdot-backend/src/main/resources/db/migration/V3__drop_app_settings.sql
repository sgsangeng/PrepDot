-- app_settings 是无 user_id 的全局表，任何登录用户都能读写他人设置（含 ai_custom_key），
-- 且前后端均无代码消费该表，直接下线
DROP TABLE IF EXISTS app_settings;
