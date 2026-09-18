package com.moviri.lab.capital;

import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
class HealthController {
    private final ObjectProvider<JdbcTemplate> database;
    private final String role;
    private final String node;

    HealthController(ObjectProvider<JdbcTemplate> database, @Value("${spring.profiles.active}") String role,
                     @Value("${demo.node}") String node) {
        this.database = database;
        this.role = role;
        this.node = node;
    }

    @GetMapping("/health")
    Map<String, String> health() {
        JdbcTemplate jdbc = database.getIfAvailable();
        if (jdbc != null) jdbc.queryForObject("select 1", Integer.class);
        return Map.of("status", "UP", "role", role, "node", node);
    }
}

@RestControllerAdvice
class ApiErrors {
    private static final Logger log = LoggerFactory.getLogger(ApiErrors.class);

    @ExceptionHandler({MethodArgumentNotValidException.class, HttpMessageNotReadableException.class})
    ResponseEntity<?> invalid(Exception ex) {
        return ResponseEntity.badRequest().body(Map.of("error", "Invalid request. Check customer, amount, term, requestId and scenario."));
    }

    @ExceptionHandler(ResponseStatusException.class)
    ResponseEntity<?> known(ResponseStatusException ex) {
        return ResponseEntity.status(ex.getStatusCode()).body(Map.of("error", ex.getReason() == null ? "Request failed" : ex.getReason()));
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<?> failure(Exception ex) {
        log.error("Demo request failed", ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(Map.of("error", "Demo request failed; inspect service logs."));
    }
}
