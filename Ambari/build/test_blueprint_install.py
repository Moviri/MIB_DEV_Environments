"""Exercise the two provisioning stages without contacting a running cluster."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("install", Path(__file__).resolve().parents[1] / "blueprint/install.py")
install = importlib.util.module_from_spec(spec)
spec.loader.exec_module(install)

HOSTS = {"items": [{"Hosts": {"host_name": f"bigtop-hostname{i}.demo.local"}} for i in range(4)]}
EMPTY = {"items": []}
VERSIONS = {"items": [{"RepositoryVersions": {"id": 7}}]}


class BlueprintTests(unittest.TestCase):
    def test_existing_cluster_or_missing_hosts_stops_before_writes(self):
        for responses in ([{"items": [{}]}], [EMPTY, EMPTY]):
            for action in ("register", "deploy"):
                api = Mock(side_effect=responses)
                with self.assertRaises(ValueError):
                    install.provision(api, action)
                self.assertTrue(all(call.args[0] == "GET" for call in api.call_args_list))

    def test_registration_sets_local_repo_and_four_host_topology(self):
        api = Mock(side_effect=[EMPTY, HOSTS, EMPTY, {}, VERSIONS, {}, {}])
        install.provision(api, "register")
        save_repo, register = [call.args for call in api.call_args_list[-2:]]
        self.assertEqual(save_repo[:2], ("PUT", install.VERSIONS + "/7"))
        os_info, = save_repo[2]["operating_systems"]
        self.assertEqual(os_info["OperatingSystems"]["os_type"], "redhat8")
        self.assertEqual(os_info["repositories"][0]["Repositories"]["base_url"], install.REPO_URL)
        self.assertEqual(register[:2], ("POST", "/blueprints/mov-ambari"))
        groups = {g["name"]: {c["name"] for c in g["components"]} for g in register[2]["host_groups"]}
        template = install.read_json("clustertemplate.json")
        for group in template["host_groups"]:
            components = groups.pop(group["name"])
            worker = group["hosts"][0]["fqdn"] != "bigtop-hostname0.demo.local"
            self.assertEqual(worker, "DATANODE" in components)
            self.assertEqual(worker, "NODEMANAGER" in components)
            self.assertNotIn("ROUTER", components)
            self.assertTrue({"HDFS_CLIENT", "YARN_CLIENT", "MAPREDUCE2_CLIENT",
                             "ZOOKEEPER_CLIENT", "METRICS_MONITOR"} <= components)
        self.assertFalse(groups)
        for entry in register[2]["configurations"]:
            props = next(iter(entry.values()))["properties"]
            self.assertFalse(any(value for key, value in props.items() if "password" in key.lower()))

    def test_deploy_checks_repo_before_submitting(self):
        for url in ("http://old.invalid/", install.REPO_URL):
            api = Mock(side_effect=[EMPTY, HOSTS, {}, VERSIONS, {"Repositories": {"base_url": url}}, {}])
            with patch.object(install.getpass, "getpass", return_value="per-install-test"):
                if url != install.REPO_URL:
                    with self.assertRaises(ValueError):
                        install.provision(api, "deploy")
                    self.assertEqual(api.call_args.args[0], "GET")
                    continue
                install.provision(api, "deploy")
            method, path, payload = api.call_args.args
            self.assertEqual((method, path), ("POST", "/clusters/mov-ambari"))
            self.assertEqual(payload["repository_version_id"], "7")
            self.assertEqual(payload["configurations"], [{"ams-grafana-env": {"metrics_grafana_password": "per-install-test"}}])
            self.assertEqual(payload["provision_action"], "INSTALL_AND_START")
