FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build
COPY pom.xml .
RUN mvn -B -ntp dependency:go-offline
COPY src ./src
RUN mvn -B -ntp package

FROM eclipse-temurin:21-jdk-jammy
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 capital && useradd --uid 10001 --gid capital --create-home capital \
    && mkdir -p /app /opt/appdynamics /tmp/appdynamics && chown -R capital:capital /app /opt/appdynamics /tmp/appdynamics
WORKDIR /app
COPY --from=build --chown=capital:capital /build/target/capital-lab.jar /app/capital-lab.jar
COPY --chown=capital:capital docker/entrypoint.sh /app/entrypoint.sh
RUN sed -i 's/\r$//' /app/entrypoint.sh && chmod +x /app/entrypoint.sh
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["/app/entrypoint.sh"]
