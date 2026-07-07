# ElasticSearch development environment

This environment starts a three-node ElasticSearch cluster and Kibana using Docker Compose. It is based on the lab setup from `python-elasticsearch/lab`, so it works for the Dynatrace ElasticSearch extension and as a local target for the Java ETL in `MIB_DEV_ElasticSearch`.

## Start the cluster

```bash
cd ElasticSearch
docker compose up -d
```

The first start creates a certificate authority and node certificates in the Docker `certs` volume. The setup container can take a few minutes to finish.

Watch setup progress:

```bash
docker compose logs -f setup
```

Check the cluster:

```bash
curl -k -u elastic:password https://localhost:9200/_cluster/health?pretty
```

Kibana is available at http://localhost:5601.

Credentials:

```text
Username: elastic
Password: password
```

## Seed sample ETL data

The stack starts empty. To add minimal `metricbeat-*` and `filebeat-*` documents for the Java ETL examples:

```bash
bash seed-etl-sample-data.sh
```

The sample documents include:

* `host.name`
* `host.os.platform`
* `system.cpu.total.pct`
* `system.memory.used.pct`
* `system.network.in.bytes`
* `event.module`
* `message`

These fields cover the standard Windows/*nix host filter examples and the generic query examples in `MIB_DEV_ElasticSearch/resources`.

## Dynatrace Extension configuration

Use this endpoint from the host running the extension:

```text
Endpoint: https://localhost:9200
Username: elastic
Password: password
```

The Compose setup uses self-signed certificates. For local development, configure the extension to allow the generated CA/self-signed certificate, or run it in the same trust context used by `python-elasticsearch/lab`.

## Java ETL configuration notes

The local Compose endpoint is HTTPS with basic authentication:

```properties
extract.elasticsearch.clientUrl=https://localhost:9200
extract.elasticsearch.authMethod=Basic
extract.elasticsearch.user=elastic
extract.elasticsearch.password=password
extract.elasticsearch.index=metricbeat-*
```

Existing sample configs such as `MIB_DEV_ElasticSearch/resources/localhost.conf` use `http://localhost:9200` and `authMethod=None`. Update those values when pointing the ETL at this Compose cluster.

For generic query testing against the seeded data, `filebeat-*` can be used with filters on `event.module`, `host.name`, or `message`.

## Stop and reset

Stop the containers:

```bash
docker compose down
```

Remove the cluster data and generated certificates:

```bash
docker compose down -v
```
