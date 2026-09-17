package com.moviri.lab.capital;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.UUID;

public final class Models {
    private Models() {}

    public enum Scenario { NORMAL, SLOW, SQL_SLOW, ERROR, CPU }

    public record Application(
            @NotNull UUID requestId,
            @Min(1) @Max(100) int customerId,
            @NotNull @DecimalMin("100.00") @DecimalMax("100000.00") @Digits(integer=6, fraction=2) BigDecimal amount,
            @Min(12) @Max(84) int termMonths,
            Scenario scenario) {
        public Application { if (scenario == null) scenario = Scenario.NORMAL; }
    }

    public record Verification(int customerId, int creditScore, boolean approved, String reason) {}
    public record ProcessRequest(@NotNull @Valid Application application, @NotNull @Valid Verification verification) {}
    public record Loan(UUID requestId, int customerId, BigDecimal amount, int termMonths,
                       String status, int creditScore, String reason, OffsetDateTime createdAt) {}
    public record Portfolio(long total, long approved, long declined, BigDecimal approvedAmount) {}
}
