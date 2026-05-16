package com.juantorchia.otel.lab;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
class AdminController {

    private final DatabaseSeeder databaseSeeder;

    AdminController(DatabaseSeeder databaseSeeder) {
        this.databaseSeeder = databaseSeeder;
    }

    @PostMapping("/admin/seed")
    Map<String, Object> seed(@RequestParam(defaultValue = "small") String size) {
        return databaseSeeder.seed(size);
    }

    @GetMapping("/admin/status")
    Map<String, Object> status() {
        return databaseSeeder.status();
    }
}
