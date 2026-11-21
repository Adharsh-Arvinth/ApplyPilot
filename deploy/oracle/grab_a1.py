"""Keep asking Oracle for the Always Free Ampere A1 server until it is created, then open HTTPS for it.

Oracle often answers "Out of capacity" for free A1 servers; capacity frees up at random, so this retries
every minute or so (politely backing off when asked to) until it gets one. Runs on your PC; needs an OCI API
key in ~/.oci/config (Profile -> Tokens and keys -> API keys). Everything it creates is Always Free.

    python deploy/oracle/grab_a1.py                 # 4 OCPU / 24 GB (the full free allowance)
    python deploy/oracle/grab_a1.py --ocpus 2 --memory 12
    python deploy/oracle/grab_a1.py --open-ports    # only open 80/443 for an existing server
"""
import argparse
import json
import os
import random
import shutil
import subprocess
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path

import oci

NAME = "applypilot-server"
SHAPE = "VM.Standard.A1.Flex"
STATE_FILE = Path.home() / ".applypilot" / "oracle-server.json"
SIZES = [(4, 24), (2, 12), (1, 6)]  # all Always Free; ApplyPilot runs on any of them
SSH_KEY = Path.home() / ".ssh" / "applypilot_oracle"
SSH_PUB = Path.home() / ".ssh" / "applypilot_oracle.pub"
REPO = Path(__file__).resolve().parents[2]
USER = "ubuntu"


def log(msg: str) -> None:
    print(f"{datetime.now():%Y-%m-%d %H:%M:%S}  {msg}", flush=True)


_LOCK = None


def single_instance() -> bool:
    """Only one copy may run (it starts at every login); a held file lock means another is running."""
    global _LOCK
    path = STATE_FILE.parent / "grab_a1.lock"
    path.parent.mkdir(parents=True, exist_ok=True)
    _LOCK = open(path, "a+")
    try:
        if sys.platform == "win32":
            import msvcrt
            _LOCK.seek(0)
            msvcrt.locking(_LOCK.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(_LOCK, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except OSError:
        return False


def clients():
    cfg = oci.config.from_file()
    oci.config.validate_config(cfg)
    kw = {"timeout": (15, 90), "retry_strategy": oci.retry.NoneRetryStrategy()}  # we pace retries ourselves
    return (cfg, oci.core.ComputeClient(cfg, **kw), oci.core.VirtualNetworkClient(cfg, **kw),
            oci.identity.IdentityClient(cfg, **kw))


def existing(compute, comp):
    for i in oci.pagination.list_call_get_all_results(compute.list_instances, comp).data:
        if i.display_name == NAME and i.lifecycle_state not in ("TERMINATED", "TERMINATING"):
            return i
    return None


def pick_subnet(net, comp):
    subnets = [s for s in oci.pagination.list_call_get_all_results(net.list_subnets, comp).data
               if s.lifecycle_state == "AVAILABLE" and not s.prohibit_public_ip_on_vnic]
    if not subnets:
        sys.exit("No public subnet found. Create a VCN with the console's 'VCN wizard' first.")
    return subnets[0]


def pick_image(compute, comp):
    imgs = compute.list_images(comp, operating_system="Canonical Ubuntu", operating_system_version="24.04",
                               shape=SHAPE, sort_by="TIMECREATED", sort_order="DESC").data
    imgs = [i for i in imgs if "Minimal" not in i.display_name]
    if not imgs:
        sys.exit("No Ubuntu 24.04 image for the A1 shape was found in this region.")
    return imgs[0]


def public_ip(compute, net, comp, inst):
    for va in compute.list_vnic_attachments(comp, instance_id=inst.id).data:
        if va.lifecycle_state == "ATTACHED":
            ip = net.get_vnic(va.vnic_id).data.public_ip
            if ip:
                return ip
    return None


def open_web_ports(net, subnet):
    """Allow HTTPS (443) and HTTP (80, only used for the certificate and the redirect to HTTPS)."""
    for sl_id in subnet.security_list_ids:
        sl = net.get_security_list(sl_id).data
        have = {(r.tcp_options.destination_port_range.min if r.tcp_options and r.tcp_options.destination_port_range else None)
                for r in sl.ingress_security_rules if r.protocol == "6" and r.source == "0.0.0.0/0"}
        rules = list(sl.ingress_security_rules)
        added = []
        for port in (80, 443):
            if port not in have:
                rules.append(oci.core.models.IngressSecurityRule(
                    protocol="6", source="0.0.0.0/0", is_stateless=False, description=f"ApplyPilot HTTPS ({port})",
                    tcp_options=oci.core.models.TcpOptions(destination_port_range=oci.core.models.PortRange(min=port, max=port))))
                added.append(port)
        if added:
            net.update_security_list(sl_id, oci.core.models.UpdateSecurityListDetails(ingress_security_rules=rules))
            log(f"Opened ports {added} in security list {sl.display_name}")
        else:
            log(f"Ports 80/443 already open in {sl.display_name}")
        return


# ───────────────────────── Install everything once the server exists ─────────────────────────
def _ssh(ip: str, command: str, timeout: int = 3600) -> subprocess.CompletedProcess:
    return subprocess.run(["ssh", "-i", str(SSH_KEY), "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=15",
                           "-o", "BatchMode=yes", f"{USER}@{ip}", command],
                          capture_output=True, text=True, timeout=timeout, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))


def _bash() -> str:
    for c in (r"C:\Program Files\Git\bin\bash.exe", r"C:\Program Files (x86)\Git\bin\bash.exe", shutil.which("bash") or ""):
        if c and Path(c).exists():
            return c
    raise RuntimeError("Git Bash not found (needed to copy the app to the server)")


def _tail(text: str, n: int = 12) -> str:
    return "\n".join((text or "").strip().splitlines()[-n:])


def deploy(ip: str) -> str:
    """Copy the app + data, run the server setup (HTTPS, free AI, service) and start it with autopilot PAUSED,
    so the laptop and the server never both apply. Returns the https address."""
    log("Waiting for SSH on the new server...")
    for _ in range(60):
        try:
            if _ssh(ip, "cloud-init status --wait >/dev/null 2>&1; echo up", timeout=900).stdout.strip().endswith("up"):
                break
        except subprocess.TimeoutExpired:
            pass
        time.sleep(10)
    else:
        raise RuntimeError("SSH never came up")

    log("Copying the app and your data to the server...")
    env = {**os.environ, "SSH_KEY": SSH_KEY.as_posix()}
    r = subprocess.run([_bash(), "deploy/oracle/push.sh", f"{USER}@{ip}", "--with-data"], cwd=REPO, env=env,
                       capture_output=True, text=True, timeout=1800, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    if r.returncode != 0:
        raise RuntimeError("copy failed:\n" + _tail(r.stdout + r.stderr))

    log("Installing on the server (packages, browser, free AI model, HTTPS) - about 15 minutes...")
    r = _ssh(ip, "bash /opt/applypilot/deploy/oracle/setup.sh 2>&1", timeout=5400)
    if r.returncode != 0:
        raise RuntimeError("setup failed:\n" + _tail(r.stdout + r.stderr, 25))
    domain = next((l.split("https://", 1)[1].strip() for l in r.stdout.splitlines() if "https://" in l and "address" in l.lower()), "")

    log("Starting ApplyPilot on the server (autopilot paused until you switch over)...")
    r = _ssh(ip, "sudo mkdir -p /etc/systemd/system/applypilot.service.d && "
                 "printf '[Service]\\nEnvironment=AUTOPILOT_ENABLED=false\\n' | sudo tee /etc/systemd/system/applypilot.service.d/paused.conf >/dev/null && "
                 "sudo systemctl daemon-reload && sudo systemctl restart applypilot && sleep 8 && systemctl is-active applypilot", timeout=300)
    if "active" not in r.stdout:
        raise RuntimeError("service didn't start:\n" + _tail(r.stdout + r.stderr))

    url = f"https://{domain}" if domain else f"https://{ip.replace('.', '-')}.sslip.io"
    for _ in range(30):  # first certificate can take a minute
        try:
            urllib.request.urlopen(url + "/api/v1/health", timeout=10)
            break
        except Exception as e:
            if getattr(e, "code", None) in (401, 403):  # reachable over HTTPS, and locked as it should be
                break
            time.sleep(10)
    return url


def notify(title: str, body: str) -> None:
    """A Windows notification plus a note on the Desktop, so the news reaches you without Claude Code."""
    note = Path.home() / "Desktop" / "ApplyPilot server.txt"
    try:
        note.write_text(f"{title}\n\n{body}\n", encoding="utf-8")
    except Exception:
        pass
    ps = ("[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null;"
          "$t = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02);"
          "$x = $t.GetElementsByTagName('text'); $x.Item(0).AppendChild($t.CreateTextNode($env:AP_T)) > $null;"
          "$x.Item(1).AppendChild($t.CreateTextNode($env:AP_B)) > $null;"
          "$id = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe';"
          "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($id).Show([Windows.UI.Notifications.ToastNotification]::new($t))")
    try:
        subprocess.run(["powershell", "-NoProfile", "-WindowStyle", "Hidden", "-Command", ps], timeout=30,
                       env={**os.environ, "AP_T": title, "AP_B": body[:200]}, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    except Exception:
        pass


def load_state() -> dict:
    try:
        return json.loads(STATE_FILE.read_text())
    except Exception:
        return {}


def save_state(**kw) -> dict:
    st = {**load_state(), **kw}
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(st, indent=2))
    return st


def finish(ip: str) -> None:
    try:
        url = deploy(ip)
    except Exception as e:
        save_state(deploy_error=str(e)[:2000])
        log(f"SETUP PROBLEM  {e}")
        notify("ApplyPilot: server created, setup needs a hand",
               f"The free Oracle server ({ip}) exists, but installing hit a problem. Open Claude Code and say: finish the Oracle server setup.")
        return
    save_state(deployed=True, url=url, deploy_error="")
    log(f"DEPLOYED  {url}  (autopilot paused until you switch over)")
    notify("ApplyPilot server is ready",
           f"{url} is set up with HTTPS and free AI. To switch: in Claude Code say 'switch to the Oracle server' "
           f"(or run deploy/oracle/switch_over.sh), then sign in on the phone with this address.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ocpus", type=float, default=4)
    ap.add_argument("--memory", type=float, default=24)
    ap.add_argument("--disk", type=int, default=100)
    ap.add_argument("--open-ports", action="store_true")
    ap.add_argument("--check", action="store_true",
                    help="don't ask Oracle; only install the server if it now exists (the PC runs this every 10 min)")
    ap.add_argument("--any-size", action="store_true", help="also try 2 OCPU / 12 GB and 1 OCPU / 6 GB (all free)")
    ap.add_argument("--log", help="append output to this file (for running hidden at login)")
    ap.add_argument("--create-only", action="store_true",
                    help="only get the server (e.g. from the always-on micro VM); the PC installs it at its next login")
    a = ap.parse_args()

    if a.log:
        f = open(a.log, "a", encoding="utf-8", buffering=1)
        sys.stdout = sys.stderr = f
    if not a.open_ports and (load_state().get("deployed") or (a.create_only and load_state().get("public_ip"))):
        log(f"Server already set up ({load_state().get('url')}); nothing to do.")
        return
    if not single_instance():
        log("Another copy is already asking Oracle; this one exits.")
        return
    st = load_state()
    if not a.open_ports and not a.create_only and st.get("public_ip"):
        log(f"Server exists at {st['public_ip']} but isn't set up yet; setting it up now.")
        finish(st["public_ip"])
        return

    cfg, compute, net, ident = clients()
    comp = cfg["tenancy"]
    subnet = pick_subnet(net, comp)
    inst = existing(compute, comp)

    if a.check and not inst:
        return  # still waiting; nothing to log every 10 minutes
    if not inst and not a.open_ports:
        ad = ident.list_availability_domains(comp).data
        image = pick_image(compute, comp)
        key = SSH_PUB.read_text().strip()
        log(f"Asking for {SHAPE} {a.ocpus:g} OCPU / {a.memory:g} GB, {a.disk} GB disk, {image.display_name}, "
            f"subnet {subnet.display_name}, {len(ad)} availability domain(s)")
        attempt = 0
        while True:
            attempt += 1
            # A request that timed out may still have created the server: never make a second one
            try:
                inst = existing(compute, comp)
            except Exception as e:  # network hiccup while checking: just try again later
                log(f"Couldn't check for the server ({type(e).__name__}); retrying")
            if inst:
                log("The server exists (an earlier request went through)")
                break
            wait = 60
            # Rotate sizes: the full free allowance first, then smaller ones that Oracle has room for far more often
            ocpus, mem = SIZES[(attempt - 1) % len(SIZES)] if a.any_size else (a.ocpus, a.memory)
            for d in ad:
                try:
                    inst = compute.launch_instance(oci.core.models.LaunchInstanceDetails(
                        compartment_id=comp, availability_domain=d.name, display_name=NAME, shape=SHAPE,
                        shape_config=oci.core.models.LaunchInstanceShapeConfigDetails(ocpus=ocpus, memory_in_gbs=mem),
                        source_details=oci.core.models.InstanceSourceViaImageDetails(image_id=image.id, boot_volume_size_in_gbs=a.disk),
                        create_vnic_details=oci.core.models.CreateVnicDetails(subnet_id=subnet.id, assign_public_ip=True),
                        metadata={"ssh_authorized_keys": key})).data
                    break
                except (oci.exceptions.RequestException, oci.exceptions.ConnectTimeout, ConnectionError, OSError) as e:
                    wait = 90
                    log(f"Attempt {attempt}: network problem talking to Oracle ({type(e).__name__}); retrying")
                    continue
                except oci.exceptions.ServiceError as e:
                    text = f"{e.code}: {e.message}"
                    if e.status == 429:
                        wait = 180
                    elif e.status == 500 or "capacity" in text.lower():
                        wait = 60
                    elif "LimitExceeded" in e.code:
                        sys.exit(f"Oracle says the free limit is already used: {text}. Delete other A1 servers first.")
                    else:
                        sys.exit(f"Oracle refused: {text}")
                    if attempt == 1 or attempt % 30 == 0:
                        log(f"Attempt {attempt}: {e.message[:110]} - retrying every ~{wait}s")
            if inst:
                break
            time.sleep(wait + random.uniform(0, 20))
        log(f"Created {NAME} after {attempt} attempt(s). Waiting for it to start...")

    inst = oci.wait_until(compute, compute.get_instance(inst.id), "lifecycle_state", "RUNNING", max_wait_seconds=1200).data
    ip = public_ip(compute, net, comp, inst)
    open_web_ports(net, subnet)
    save_state(name=NAME, id=inst.id, public_ip=ip, shape=inst.shape, created=str(inst.time_created))
    log(f"READY  {NAME} is running at {ip}  (saved to {STATE_FILE})")
    if a.create_only:
        log("Created. The PC sets it up at its next login (it finds the server by name).")
    elif not a.open_ports:
        notify("ApplyPilot: got the free Oracle server!", f"Server {ip} created. Installing everything now (about 20 minutes)...")
        finish(ip)


if __name__ == "__main__":
    main()
