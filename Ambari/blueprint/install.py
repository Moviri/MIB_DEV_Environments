"""Trial deployment of the four-node profile on a freshly bootstrapped Ambari 3 server."""
import argparse
import base64
import getpass
import http.client
import json
import secrets
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
VERSIONS = "/stacks/BIGTOP/versions/3.3.0/repository_versions"
REPO_URL = "http://bigtop-hostname0.demo.local/"
REPO_ID = "BIGTOP-3.3.0"


def read_json(filename):
    return json.loads((HERE / filename).read_text())


def repository_id(api):
    versions = api("GET", VERSIONS)["items"]
    if len(versions) != 1:
        raise ValueError(f"Expected one BIGTOP 3.3.0 repository version, found {len(versions)}.")
    return int(versions[0]["RepositoryVersions"]["id"])


def provision(api, action):
    template = read_json("clustertemplate.json")
    cluster = template["Clusters"]["cluster_name"]
    blueprint_path = "/blueprints/" + template["blueprint"]

    if api("GET", "/clusters")["items"]:
        raise ValueError("This server already has a cluster. Use a separate fresh instance.")
    expected = {host["fqdn"] for group in template["host_groups"] for host in group["hosts"]}
    registered = {item["Hosts"]["host_name"] for item in api("GET", "/hosts")["items"]}
    if registered != expected:
        raise ValueError(f"Check agent registration. Expected {sorted(expected)}, found {sorted(registered)}.")

    if action == "register":
        if not api("GET", VERSIONS)["items"]:
            api("POST", "/version_definitions", {"VersionDefinition": {"available": "BIGTOP-3.3.0"}})
        version = repository_id(api)
        api("PUT", f"{VERSIONS}/{version}", {"operating_systems": [{
            "OperatingSystems": {"os_type": "redhat8", "ambari_managed_repositories": True},
            "repositories": [{"Repositories": {"repo_id": REPO_ID, "repo_name": "bigtop", "base_url": REPO_URL}}],
        }]})
        api("POST", blueprint_path, read_json("blueprint.json"))
        print("Blueprint registered. Run the deploy command to install and start services.")
        return

    api("GET", blueprint_path)
    version = repository_id(api)
    repo = api("GET", f"{VERSIONS}/{version}/operating_systems/redhat8/repositories/{REPO_ID}?fields=Repositories/base_url")
    if repo["Repositories"]["base_url"].rstrip("/") != REPO_URL.rstrip("/"):
        raise ValueError("The registered Rocky 8 repository does not point to node 0.")

    grafana = getpass.getpass("New Metrics Grafana admin password: ")
    if not grafana.strip():
        raise ValueError("Enter a nonempty Grafana password.")
    template["configurations"].append({"ams-grafana-env": {"metrics_grafana_password": grafana}})
    template["default_password"] = secrets.token_hex(24)
    template["repository_version_id"] = str(version)
    result = api("POST", "/clusters/" + cluster, template)
    print(f"Ambari accepted the installation. Open Background Operations for {cluster}.")
    if result.get("href"):
        print("Request:", result["href"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("register", "deploy"))
    args = parser.parse_args()
    password = getpass.getpass("Local Ambari admin password: ")
    token = base64.b64encode(("admin:" + password).encode()).decode()
    headers = {"Authorization": "Basic " + token, "X-Requested-By": "ambari", "Content-Type": "application/json"}

    def api(method, path, payload=None):
        connection = http.client.HTTPConnection("127.0.0.1", 8080, timeout=120)
        try:
            connection.request(method, "/api/v1" + path, json.dumps(payload) if payload is not None else None, headers)
            response = connection.getresponse()
            body = response.read()
            if not 200 <= response.status < 300:
                message = body.decode(errors="replace")
                if method == "POST" and path.startswith("/clusters/"):
                    try:
                        message = json.loads(body)["message"]
                    except (ValueError, KeyError, TypeError):
                        message = response.reason
                    grafana = payload["configurations"][-1]["ams-grafana-env"]["metrics_grafana_password"]
                    for secret in (grafana, payload["default_password"]):
                        message = message.replace(secret, "[redacted]")
                raise ValueError(f"{method} {path}: HTTP {response.status} {message}")
            return json.loads(body) if body.strip() else {}
        finally:
            connection.close()

    provision(api, args.action)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, http.client.HTTPException) as error:
        sys.exit(str(error))
