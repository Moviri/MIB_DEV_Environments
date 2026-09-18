"""Import a Controller-configured Java Agent ZIP without printing its access key."""
import argparse
import os
from pathlib import Path
import re
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--host-id", default="capital-lab-host-01")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", args.host_id):
        parser.error("Use letters, digits, dots, dashes or underscores in the host ID.")
    destination = ROOT / "agents" / "java"
    if (destination / "javaagent.jar").exists():
        raise SystemExit("Agent already installed. Use a separate clean lab folder when changing the distribution.")
    with zipfile.ZipFile(args.archive) as archive:
        for entry in archive.infolist():
            path = (destination / entry.filename).resolve()
            if not path.is_relative_to(destination.resolve()):
                raise SystemExit("Archive contains a path outside the agent directory.")
        archive.extractall(destination)
    if not (destination / "javaagent.jar").is_file():
        raise SystemExit("Expected javaagent.jar at the ZIP root; use the full standard Java Agent ZIP.")
    configs = sorted(destination.rglob("controller-info.xml"), key=lambda p: len(p.parts))
    if not configs:
        raise SystemExit("No controller-info.xml found in the agent archive.")
    config = ET.parse(configs[0]).getroot()
    fields = {
        "APPDYNAMICS_CONTROLLER_HOST_NAME": "controller-host",
        "APPDYNAMICS_CONTROLLER_PORT": "controller-port",
        "APPDYNAMICS_CONTROLLER_SSL_ENABLED": "controller-ssl-enabled",
        "APPDYNAMICS_AGENT_ACCOUNT_NAME": "account-name",
        "APPDYNAMICS_AGENT_ACCOUNT_ACCESS_KEY": "account-access-key",
    }
    values = {key: (config.findtext(tag) or "").strip() for key, tag in fields.items()}
    if any(not value for value in values.values()):
        raise SystemExit("Agent extracted, but the ZIP has incomplete Controller settings. Fill .env from .env.example manually.")
    if any("\n" in value or "\r" in value or "'" in value or "\\" in value for value in values.values()):
        raise SystemExit("Settings contain unexpected characters; configure .env manually.")
    values.update(APPDYNAMICS_ENABLED="true", APPDYNAMICS_AGENT_APPLICATION_NAME="Capital-Lab",
                  APPDYNAMICS_AGENT_UNIQUE_HOST_ID=args.host_id)
    env_path = ROOT / ".env"
    original = (env_path if env_path.exists() else ROOT / ".env.example").read_text(encoding="utf-8")
    for key, value in values.items():
        line = key + "='" + value + "'"
        if re.search(r"^" + key + "=", original, re.MULTILINE):
            original = re.sub(r"^" + key + r"=.*$", lambda _: line, original, flags=re.MULTILINE)
        else:
            original += "\n" + line + "\n"
    env_path.write_text(original, encoding="utf-8")
    if os.name != "nt":
        env_path.chmod(0o600)
    print("Java Agent extracted; Controller settings saved to ignored .env. Access key was not printed.")
    print("Application: Capital-Lab; host ID: " + args.host_id)


if __name__ == "__main__":
    main()
