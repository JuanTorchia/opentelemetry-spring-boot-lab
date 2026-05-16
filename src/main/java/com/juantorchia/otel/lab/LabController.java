package com.juantorchia.otel.lab;

import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
class LabController {

    private final LabService labService;

    LabController(LabService labService) {
        this.labService = labService;
    }

    @GetMapping("/lab/baseline")
    Map<String, Object> baseline() {
        return labService.baseline();
    }

    @GetMapping("/lab/n-plus-one")
    Map<String, Object> nPlusOne(@RequestParam(defaultValue = "60") int limit) {
        return labService.nPlusOne(limit);
    }

    @GetMapping("/lab/optimized")
    Map<String, Object> optimized(@RequestParam(defaultValue = "60") int limit) {
        return labService.optimized(limit);
    }

    @GetMapping("/lab/downstream-slow")
    Map<String, Object> downstreamSlow(@RequestParam(defaultValue = "300") int delayMs) {
        return labService.downstreamSlow(delayMs);
    }

    @GetMapping("/lab/mixed")
    Map<String, Object> mixed(
            @RequestParam(defaultValue = "300") int delayMs,
            @RequestParam(defaultValue = "12") int limit) {
        return labService.mixed(delayMs, limit);
    }

    @GetMapping("/lab/partial-error")
    ResponseEntity<Map<String, Object>> partialError(@RequestParam(defaultValue = "100") int delayMs) {
        return ResponseEntity.status(HttpStatus.PARTIAL_CONTENT).body(labService.partialError(delayMs));
    }
}
