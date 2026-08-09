package com.prepdot.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.prepdot.entity.AppSettings;
import com.prepdot.mapper.AppSettingsMapper;
import com.prepdot.service.SettingsService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class SettingsServiceImpl implements SettingsService {

    private final AppSettingsMapper settingsMapper;

    @Override
    public Map<String, String> getAll() {
        List<AppSettings> list = settingsMapper.selectList(null);
        return list.stream().collect(
                Collectors.toMap(AppSettings::getSettingKey, AppSettings::getSettingValue)
        );
    }

    @Override
    @Transactional
    public void saveAll(Map<String, String> settings) {
        settings.forEach((key, value) -> {
            AppSettings existing = settingsMapper.selectOne(
                    new LambdaQueryWrapper<AppSettings>()
                            .eq(AppSettings::getSettingKey, key)
            );
            if (existing == null) {
                AppSettings s = new AppSettings();
                s.setSettingKey(key);
                s.setSettingValue(value);
                settingsMapper.insert(s);
            } else {
                existing.setSettingValue(value);
                settingsMapper.updateById(existing);
            }
        });
    }
}
