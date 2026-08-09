package com.prepdot.service;

import java.util.Map;

public interface SettingsService {

    Map<String, String> getAll();

    void saveAll(Map<String, String> settings);
}
