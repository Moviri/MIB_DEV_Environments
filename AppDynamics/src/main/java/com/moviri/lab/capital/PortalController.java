package com.moviri.lab.capital;

import jakarta.validation.Valid;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.server.ResponseStatusException;
import static com.moviri.lab.capital.Models.*;

@RestController
@Profile("portal")
class PortalController {
    private final RestClient verification;
    private final RestClient processor;

    PortalController(@Value("${demo.verification-url}") String verificationUrl,
                     @Value("${demo.processor-url}") String processorUrl) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(3000);
        factory.setReadTimeout(10000);
        verification = RestClient.builder().requestFactory(factory).baseUrl(verificationUrl).build();
        processor = RestClient.builder().requestFactory(factory).baseUrl(processorUrl).build();
    }

    @PostMapping("/api/loans/apply")
    Loan apply(@Valid @RequestBody Application request) {
        try {
            Verification decision = verification.post().uri("/internal/verify").body(request).retrieve().body(Verification.class);
            return processor.post().uri("/internal/process").body(new ProcessRequest(request, decision)).retrieve().body(Loan.class);
        } catch (RestClientResponseException ex) {
            throw new ResponseStatusException(ex.getStatusCode(), "Downstream request failed (" + ex.getStatusCode().value() + ").", ex);
        } catch (ResourceAccessException ex) {
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Downstream service unavailable.", ex);
        }
    }

    @GetMapping("/api/loans/recent")
    List<Loan> recent() {
        Loan[] loans = processor.get().uri("/internal/loans/recent").retrieve().body(Loan[].class);
        return loans == null ? List.of() : List.of(loans);
    }

    @GetMapping("/api/reports/portfolio")
    Portfolio portfolio() {
        return processor.get().uri("/internal/reports/portfolio").retrieve().body(Portfolio.class);
    }
}
