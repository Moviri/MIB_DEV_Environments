"""Run against the actual three services and PostgreSQL, with loadgen stopped."""
import concurrent.futures
import json
import os
import time
import urllib.error
import urllib.request
import uuid

TARGET = os.getenv("TARGET_URL", "http://localhost:8088").rstrip("/")


def call(path, body=None):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(TARGET + path, data, {"Content-Type": "application/json"})
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, json.load(response), time.monotonic() - started
    except urllib.error.HTTPError as error:
        return error.code, json.load(error), time.monotonic() - started


def application(**changes):
    result = dict(requestId=str(uuid.uuid4()), customerId=10, amount=1234.56, termMonths=24, scenario="NORMAL")
    return result | changes


def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print("PASS " + message, flush=True)


def main():
    code, health, _ = call("/health")
    check(code == 200 and health["status"] == "UP", "Portal is healthy")
    baseline = call("/api/reports/portfolio")[1]
    submitted = application()
    code, loan, _ = call("/api/loans/apply", submitted)
    check(code == 200 and loan["status"] == "APPROVED" and loan["amount"] == 1234.56,
          "Approval crosses all three tiers and preserves decimal amount")
    check(call("/api/loans/apply", submitted)[1] == loan, "Identical retry returns the original loan")
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        retries = list(executor.map(lambda _: call("/api/loans/apply", submitted), range(6)))
    check(all(r[0] == 200 and r[1] == loan for r in retries), "Concurrent retries are idempotent")
    check(call("/api/loans/apply", submitted | {"amount": 2000})[0] == 409,
          "Reusing requestId for different data is rejected")
    code, declined, _ = call("/api/loans/apply", application(customerId=1))
    check(code == 200 and declined["status"] == "DECLINED", "Business decline is a successful transaction")
    for changes in ({"amount": -5}, {"amount": 100.123}, {"customerId": 101},
                    {"termMonths": 0}, {"scenario": "UNKNOWN"}, {"requestId": "not-a-uuid"}):
        check(call("/api/loans/apply", application(**changes))[0] == 400, "Input rejected: " + str(changes))
    check(call("/api/loans/apply", application(scenario="ERROR"))[0] == 500,
          "Injected verification error reaches the portal as HTTP 500")
    code, _, elapsed = call("/api/loans/apply", application(scenario="SLOW"))
    check(code == 200 and elapsed >= 1.8, "Slow verification produces measurable latency")
    code, _, elapsed = call("/api/loans/apply", application(scenario="SQL_SLOW"))
    check(code == 200 and elapsed >= 1.3, "Slow SQL executes against PostgreSQL")
    check(call("/api/loans/apply", application(scenario="CPU"))[0] == 200, "Bounded CPU workload completes")
    recent = call("/api/loans/recent")[1]
    check(sum(row["requestId"] == submitted["requestId"] for row in recent) == 1,
          "Exactly one original loan is persisted after retries")
    final = call("/api/reports/portfolio")[1]
    check(final["total"] == baseline["total"] + 5 and final["approved"] == baseline["approved"] + 4
          and final["declined"] == baseline["declined"] + 1,
          "Portfolio totals exclude failed requests and duplicate retries")
    print("All workflow checks passed. Five synthetic loans were added.")


if __name__ == "__main__":
    main()
