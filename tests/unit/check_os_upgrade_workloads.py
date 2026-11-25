"""Check the workload snippets of ansible/playbooks/os-upgrade.yml.

1. On a Docker-only host (vega, rigel) every snippet must print exactly what
   the pre-Proxmox playbook printed, so the change is a no-op for the Pis.
2. On a Proxmox host the running VMs appear as "vm:<name>", and the restart
   policy check marks VMs without onboot as "no-onboot".

Runs inside the ansible-runner container with fake docker/qm commands on
PATH; see scripts/test-os-upgrade-workloads.sh.
"""
import os
import subprocess
import sys

import jinja2
import yaml

PLAYBOOK = "ansible/playbooks/os-upgrade.yml"
FAKES = "tests/unit/fakes/os-upgrade"

# The commands the playbook ran before VMs were added (main at 304900d).
MAIN_BEFORE = "docker ps --format '{{.Names}}' | sort"
MAIN_REBOOT = "docker ps --filter status=running --format '{{.Names}}' | sort"
MAIN_POLICY = (
    "docker ps -q | xargs -r docker inspect "
    "--format '{{.Name}} {{.HostConfig.RestartPolicy.Name}}' | sed 's#^/##' | sort"
)


def load():
    play = yaml.safe_load(open(PLAYBOOK))[0]
    env = jinja2.Environment()
    ctx = {}
    for key in ("os_upgrade_vms_sh", "os_upgrade_workloads_sh",
                "os_upgrade_running_workloads_sh"):
        ctx[key] = env.from_string(play["vars"][key]).render(**ctx)
    block = next(t for t in play["tasks"] if t.get("name") == "Reboot and verify")["block"]
    policy = next(t for t in block if t["name"].startswith("Record each running"))["shell"]
    order = os.path.abspath(f"{FAKES}/vm-start-order")
    ctx["policy"] = env.from_string(policy).render(os_upgrade_unlock_order_file=order)
    ctx["policy_no_order"] = env.from_string(policy).render(
        os_upgrade_unlock_order_file="/nonexistent/vm-start-order")
    return ctx


def run_rc(cmd, path_dirs, extra_env=None):
    env = dict(os.environ, PATH=":".join(path_dirs + ["/usr/bin", "/bin"]), **(extra_env or {}))
    res = subprocess.run(["bash", "-c", "set -o pipefail\n" + cmd],
                         capture_output=True, text=True, env=env)
    return res.returncode, res.stdout


def run(cmd, path_dirs):
    rc, out = run_rc(cmd, path_dirs)
    if rc != 0:
        raise AssertionError(f"command failed ({rc}): {cmd[:60]}")
    return out


def main():
    ctx = load()
    failures = 0
    docker_only = [os.path.abspath(f"{FAKES}/docker")]
    proxmox = docker_only + [os.path.abspath(f"{FAKES}/qm")]
    vms_only = [os.path.abspath(f"{FAKES}/qm")]

    checks = [
        ("docker-only: before/after upgrade", run(ctx["os_upgrade_workloads_sh"], docker_only),
         run(MAIN_BEFORE, docker_only)),
        ("docker-only: after reboot", run(ctx["os_upgrade_running_workloads_sh"], docker_only),
         run(MAIN_REBOOT, docker_only)),
        ("docker-only: restart policies", run(ctx["policy"], docker_only),
         run(MAIN_POLICY, docker_only)),
        ("proxmox+docker: workloads", run(ctx["os_upgrade_workloads_sh"], proxmox),
         "db\nrestarter\nvm:alkaid\nvm:dubhe\nweb\n"),
        ("proxmox only: running workloads", run(ctx["os_upgrade_running_workloads_sh"], vms_only),
         "vm:alkaid\nvm:dubhe\n"),
        ("proxmox only: restart policies (alkaid started after unlock)",
         run(ctx["policy"], vms_only),
         "vm:alkaid after-unlock\nvm:dubhe always\n"),
        ("proxmox only: restart policies (no unlock list)",
         run(ctx["policy_no_order"], vms_only),
         "vm:alkaid no-onboot\nvm:dubhe always\n"),
        ("docker-only: restart policies ignore the unlock list",
         run(ctx["policy_no_order"], docker_only), run(MAIN_POLICY, docker_only)),
    ]
    # A failing Docker daemon must fail every snippet, exactly as the old
    # commands did (the playbook then stops before upgrading or rebooting).
    fail_env = {"FAKE_DOCKER_FAIL": "1"}
    for name, new_cmd, old_cmd in [
        ("before/after upgrade", ctx["os_upgrade_workloads_sh"], MAIN_BEFORE),
        ("after reboot", ctx["os_upgrade_running_workloads_sh"], MAIN_REBOOT),
        ("restart policies", ctx["policy"], MAIN_POLICY),
    ]:
        new_rc, _ = run_rc(new_cmd, docker_only, fail_env)
        old_rc, _ = run_rc(old_cmd, docker_only, fail_env)
        checks.append((f"docker down: {name} fails (rc {new_rc}; old rc {old_rc})",
                       (new_rc != 0, old_rc != 0), (True, True)))

    for name, got, want in checks:
        ok = got == want
        failures += not ok
        print(f"{'PASS' if ok else 'FAIL'}  {name}")
        if not ok:
            print(f"      want {want!r}\n      got  {got!r}")
    if failures:
        sys.exit(f"{failures} check(s) failed")
    print("All os-upgrade workload checks passed.")


if __name__ == "__main__":
    main()
