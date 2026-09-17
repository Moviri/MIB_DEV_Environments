# Local validation — September 17, 2026

Validated on Windows Docker Desktop using its Linux engine. This report describes the local run, not a Boston deployment.

- Built the application with Java 21 and Spring Boot 3.5.16 inside Docker.
- Installed the configured AppDynamics Java Agent 26.7.0.38091 from the trial Controller's download wizard. Its connection settings are kept in the ignored `.env` and agent directory.
- PostgreSQL reported version 17.11 in the Controller's discovered JDBC backend.
- All four core services passed Compose health checks; the load generator is a fifth running container.
- The 18 checks in `scripts/smoke.py` passed both without and with the Java agent, using the real three services and PostgreSQL. Each run added five synthetic loan decisions.
- A browser form submission returned an approved loan, and the live ledger and portfolio refreshed successfully. The interface was visually inspected.
- AppDynamics displayed **Capital-Lab**, tiers **Portal**, **Verification**, **Loan-Processing**, and **three healthy nodes**.
- The Controller displayed both HTTP links from Portal and JDBC calls from Verification and Loan-Processing to PostgreSQL.
- During validation, the Controller showed roughly 4,700 calls, 298 slow transactions, 299 very slow transactions, and **106 intentional errors**. These are a point-in-time observation; ongoing load and the selected time window change them.
- The generator's corresponding logs showed **106 HTTP 500 responses**, demonstrating that injected errors reached AppDynamics.
- Changed this application's Java servlet naming rule from the first two URI segments to the full URI so each stable demo API route can be discovered separately.
- Built and inspected the source-only deployment ZIP; it excludes `.env`, downloaded agent payloads, logs and build outputs.

Not validated here: execution of the Moviri/BMC ETL itself, Boston host deployment, Linux Machine Agent hardware collection, Database Agent server metrics, or Analytics/EUM. The README and Linux guide describe the prerequisites for those follow-on checks. AppDynamics JDBC timing is verified; it is not equivalent to Database Visibility server telemetry.
