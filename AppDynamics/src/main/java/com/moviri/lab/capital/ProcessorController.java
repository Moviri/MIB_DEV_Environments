package com.moviri.lab.capital;

import jakarta.validation.Valid;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import static com.moviri.lab.capital.Models.*;

@RestController
@Profile("processor")
class ProcessorController {
    private final JdbcTemplate jdbc;
    private final boolean failuresEnabled;

    ProcessorController(JdbcTemplate jdbc, @Value("${demo.failures-enabled}") boolean failuresEnabled) {
        this.jdbc = jdbc;
        this.failuresEnabled = failuresEnabled;
    }

    @PostMapping("/internal/process")
    @Transactional
    public Loan process(@Valid @RequestBody ProcessRequest request) {
        Application application = request.application();
        Verification verification = request.verification();
        if (application.customerId() != verification.customerId()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Customer mismatch.");
        }
        if (application.scenario() == Scenario.SQL_SLOW) {
            if (!failuresEnabled) throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Fault scenarios are disabled.");
            // A real JDBC round trip: AppDynamics can attribute the delay to the database backend.
            jdbc.query("select pg_sleep(1.5)", (row, number) -> 0);
        }
        jdbc.update("""
                insert into loans(request_id, customer_id, amount, term_months, status, credit_score, reason)
                values (?, ?, ?, ?, ?, ?, ?) on conflict (request_id) do nothing
                """, application.requestId(), application.customerId(), application.amount(), application.termMonths(),
                verification.approved() ? "APPROVED" : "DECLINED", verification.creditScore(), verification.reason());
        Loan loan = jdbc.queryForObject("select * from loans where request_id = ?", this::readLoan, application.requestId());
        if (loan == null || loan.customerId() != application.customerId() || loan.amount().compareTo(application.amount()) != 0
                || loan.termMonths() != application.termMonths()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "requestId was already used for a different application.");
        }
        return loan;
    }

    @GetMapping("/internal/loans/recent")
    List<Loan> recent() {
        return jdbc.query("select * from loans order by created_at desc, request_id limit 30", this::readLoan);
    }

    @GetMapping("/internal/reports/portfolio")
    Portfolio portfolio() {
        return jdbc.queryForObject("""
                select count(*) as total,
                       count(*) filter (where status = 'APPROVED') as approved,
                       count(*) filter (where status = 'DECLINED') as declined,
                       coalesce(sum(amount) filter (where status = 'APPROVED'), 0) as approved_amount from loans
                """, (row, number) -> new Portfolio(row.getLong("total"), row.getLong("approved"),
                row.getLong("declined"), row.getBigDecimal("approved_amount")));
    }

    private Loan readLoan(ResultSet row, int number) throws SQLException {
        return new Loan(row.getObject("request_id", UUID.class), row.getInt("customer_id"), row.getBigDecimal("amount"),
                row.getInt("term_months"), row.getString("status"), row.getInt("credit_score"), row.getString("reason"),
                row.getObject("created_at", OffsetDateTime.class));
    }
}
