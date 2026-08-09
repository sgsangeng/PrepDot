package com.prepdot;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
@MapperScan("com.prepdot.mapper")
public class PrepDotApplication {
    public static void main(String[] args) {
        SpringApplication.run(PrepDotApplication.class, args);
    }
}
