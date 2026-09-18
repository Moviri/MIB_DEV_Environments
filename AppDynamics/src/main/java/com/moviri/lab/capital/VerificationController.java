package com.moviri.lab.capital;

import jakarta.validation.Valid;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import static com.moviri.lab.capital.Models.*;

@RestController
@Profile("verification")
class VerificationController {
    private final JdbcTemplate jdbc;
    private final boolean failuresEnabled;
    private volatile int cpuResult;

    VerificationController(JdbcTemplate jdbc, @Value("${demo.failures-enabled}") boolean failuresEnabled) {
        this.jdbc = jdbc;
        this.failuresEnabled = failuresEnabled;
    }

    @PostMapping("/internal/verify")
    Verification verify(@Valid @RequestBody Application request) throws Exception {
        if (!failuresEnabled && request.scenario() != Scenario.NORMAL) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Fault scenarios are disabled.");
        }
        if (request.scenario() == Scenario.ERROR) {
            throw new IllegalStateException("Synthetic verification failure requested by scenario ERROR");
        }
        if (request.scenario() == Scenario.SLOW) Thread.sleep(2000);
        else Thread.sleep(25);
        if (request.scenario() == Scenario.CPU) {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] value = request.requestId().toString().getBytes(StandardCharsets.UTF_8);
            long stop = System.nanoTime() + 300_000_000L;
            do { value = digest.digest(value); } while (System.nanoTime() < stop);
            cpuResult = value[0];
        }
        Integer score = jdbc.queryForObject("select credit_score from customers where id = ?", Integer.class, request.customerId());
        boolean approved = score != null && score >= 660;
        return new Verification(request.customerId(), score == null ? 0 : score, approved,
                approved ? "Demo credit threshold met" : "Demo credit threshold not met");
    }
}
