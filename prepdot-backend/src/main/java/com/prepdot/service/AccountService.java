package com.prepdot.service;

public interface AccountService {

    /** 校验密码并永久删除账号及其关联学习数据。 */
    void deleteAccount(Long userId, String password);
}
