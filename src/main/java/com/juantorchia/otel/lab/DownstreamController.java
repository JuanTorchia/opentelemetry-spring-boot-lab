package com.juantorchia.otel.lab;

import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
class DownstreamController {

    @GetMapping("/downstream/profile")
    ResponseEntity<Map<String, Object>> profile(
            @RequestParam(defaultValue = "50") int delayMs,
            @RequestParam(defaultValue = "false") boolean fail) throws InterruptedException {
        Thread.sleep(Math.max(0, delayMs));
        if (fail) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("status", "error", "delayMs", delayMs));
        }
        return ResponseEntity.ok(Map.of(
                "status", "ok",
                "delayMs", delayMs,
                "profile", "synthetic-downstream"));
    }
}
