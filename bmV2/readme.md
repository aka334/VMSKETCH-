# VMSketch

VMSketch is a P4-based network measurement sketch with a small Python CLI helper and a Jupyter notebook for experiments. This README explains how we (a) create and use a **FABRIC Testbed** slice via the notebook, and (b) run the P4 program on **bmv2** (locally or on your FABRIC nodes), initialize tables/registers, and exercise it with test traffic.

---

## Repository Layout

* `VMSKETCH.p4` – P4 program implementing the sketch and basic L2 forwarding.
* `init_vmsketch_cli.py` – prints CLI commands to initialize tables/registers for the P4 pipeline.
* `VMSketch.ipynb` – end-to-end walkthrough: slice creation on FABRIC, node setup, and runtime checks.

---

## Prerequisites

* **Python** 3.8+
* **P4 toolchain**

  * `p4c` (P4 compiler, v1model)
  * **bmv2** (behavioral model) with `simple_switch` and `simple_switch_CLI`
* **Jupyter** (for the notebook path)
* **Traffic tools** (choose any): `ping`, `iperf3`, or Python `scapy`
* (FABRIC) FABRIC account/access, SSH key uploaded, and FABRIC Python SDK (`fabrictestbed-extensions`) installed in the notebook environment.

---

## A. Create a FABRIC Slice (via the Notebook)

We use the `VMSketch.ipynb` notebook to request a slice with two host nodes connected by a L2 network (you can extend to more nodes/links as needed).

**High-level steps covered in the notebook:**

1. **Authenticate to FABRIC**: load your FABRIC tokens/credentials in the notebook (typically via environment variables or the FABRIC tutorial cell).
2. **Define the slice**:

   * Two compute nodes (e.g., `nodeA`, `nodeB`) running Ubuntu.
   * One L2 network connecting both nodes (e.g., VLAN-backed or FABRIC site switch attachment).
3. **Submit & wait for provisioning**: the notebook polls the slice state until it becomes `Stable`.
4. **Configure interfaces** on both nodes (IP addresses if needed) and verify basic reachability (`ping`).
5. **Install P4 dependencies** on the node where you’ll run the switch

> **Notebook outputs**: Once the slice is ready, the notebook cells show assigned public IPs and provide convenience SSH commands.

---

## C. Run the P4 Program on bmv2 (Local or FABRIC)

1. **Copy project files** to the switch host:

```bash
# On your laptop
scp VMSKETCH.p4 init_vmsketch_cli.py <user>@<host>:/home/<user>/vmsketch/
# Or use the notebook to push files with fablib's nX.upload_file(...)
```

2. **Compile the P4 program**:

```bash
cd ~/vmsketch
p4c --target bmv2 --arch v1model --std p4-16 \
    -o build VMSKETCH.p4
# This produces build/VMSKETCH.json (and P4Info if requested via --p4runtime-files)
```

3. **Program tables & registers** using the helper script:

```bash
python3 init_vmsketch_cli.py | simple_switch_CLI
```

4. **Generate traffic** between hosts to exercise the sketch:

```bash
sudo ip netns exec h1 ping -c 3 10.0.0.2
# Or use iperf3 / scapy for higher volume flows
```

---

## Quick Reference

```bash
# Compile
p4c --target bmv2 --arch v1model --std p4-16 -o build VMSKETCH.p4

# Run switch
sudo simple_switch -i 1@veth1 -i 2@veth2 build/VMSKETCH.json --log-console &

# Init pipeline
python3 init_vmsketch_cli.py | simple_switch_CLI

# Send traffic
sudo ip netns exec h1 ping -c 3 10.0.0.2

# Inspect state
simple_switch_CLI
> show_tables
> register_read <reg> 0 16
```

---

