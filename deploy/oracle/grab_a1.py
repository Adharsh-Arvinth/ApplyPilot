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
import random
import sys
import time
from datetime import datetime
from pathlib import Path

import oci

NAME = "applypilot-server"
SHAPE = "VM.Standard.A1.Flex"
STATE_FILE = Path.home() / ".applypilot" / "oracle-server.json"
SSH_PUB = Path.home() / ".ssh" / "applypilot_oracle.pub"


def log(msg: str) -> None:
    print(f"{datetime.now():%Y-%m-%d %H:%M:%S}  {msg}", flush=True)


def clients():
    cfg = oci.config.from_file()
    oci.config.validate_config(cfg)
    return cfg, oci.core.ComputeClient(cfg), oci.core.VirtualNetworkClient(cfg), oci.identity.IdentityClient(cfg)


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ocpus", type=float, default=4)
    ap.add_argument("--memory", type=float, default=24)
    ap.add_argument("--disk", type=int, default=100)
    ap.add_argument("--open-ports", action="store_true")
    a = ap.parse_args()

    cfg, compute, net, ident = clients()
    comp = cfg["tenancy"]
    subnet = pick_subnet(net, comp)
    inst = existing(compute, comp)

    if not inst and not a.open_ports:
        ad = ident.list_availability_domains(comp).data
        image = pick_image(compute, comp)
        key = SSH_PUB.read_text().strip()
        log(f"Asking for {SHAPE} {a.ocpus:g} OCPU / {a.memory:g} GB, {a.disk} GB disk, {image.display_name}, "
            f"subnet {subnet.display_name}, {len(ad)} availability domain(s)")
        attempt = 0
        while True:
            attempt += 1
            for d in ad:
                try:
                    inst = compute.launch_instance(oci.core.models.LaunchInstanceDetails(
                        compartment_id=comp, availability_domain=d.name, display_name=NAME, shape=SHAPE,
                        shape_config=oci.core.models.LaunchInstanceShapeConfigDetails(ocpus=a.ocpus, memory_in_gbs=a.memory),
                        source_details=oci.core.models.InstanceSourceViaImageDetails(image_id=image.id, boot_volume_size_in_gbs=a.disk),
                        create_vnic_details=oci.core.models.CreateVnicDetails(subnet_id=subnet.id, assign_public_ip=True),
                        metadata={"ssh_authorized_keys": key})).data
                    break
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
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps({"name": NAME, "id": inst.id, "public_ip": ip, "shape": inst.shape,
                                      "created": str(inst.time_created)}, indent=2))
    log(f"READY  {NAME} is running at {ip}  (saved to {STATE_FILE})")


if __name__ == "__main__":
    main()
