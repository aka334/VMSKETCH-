# VMSketch (Tofino / “actual P4 switch” quick guide)

VMSketch is a P4-based network measurement sketch. This short README focuses on **running on real P4 switches (Intel® Tofino / TNA)** with BF SDE + BFRT. A minimal bmv2 snippet is left at the end for local sanity checks.

---

## Repository Layout

* `vmsketch_tna.p4` – TNA P4 program for Tofino.
* `init_vmsketch_bfrt.py` – BFRT init script (loads table entries, initializes registers).
* `tofinoswitchTNA.ipynb` – simple walkthrough for compiling, loading, and testing on a Tofino target.
---

## Prerequisites (Tofino)

* **BF SDE** installed on the switch server (version matching your ASIC/OS image)
* `bf_switchd` and BFRT Python available (`bfrt_python`)
* `bf-p4c` / `p4_build.sh` toolchain for **TNA**
* Access to the switch’s **ports** (cabled hosts/testers) and basic out-of-band management

> Ask your site admin for the exact SDE path (e.g., `/opt/bf-sde-<ver>/`) and platform config file (e.g., `conf/tdi.json` or `<platform>_conf.json`).

---

---

## A. Run `bf_switchd` with the Program

Launch the switch daemon pointing to your platform config and the compiled program:

```bash
sudo -E $SDE/run_switchd.sh -p vmsketch -c $SDE/share/p4/targets/tofino/tofino_skip_p4.conf \
  -f /path/to/<platform>_conf.json
```

Common variations:

* Some installs use: `sudo -E $SDE/run_bfshell.sh -f <platform>_conf.json -b` under the hood.
* If your image expects a different conf path, use it (ask your admin).

When `bf_switchd` is up, you should see logs indicating the pipeline is loaded and ports are initialized.

---

## B. Initialize Tables & Registers (BFRT)

Run the provided BFRT Python script to set default entries and register seeds/values:

```bash
$SDE/run_bfshell.sh -b init_vmsketch_bfrt.py
```

What it typically does:

* Programs basic L2 forwarding (or default actions) as examples
* Initializes sketch-related **registers** (e.g., seeds, counters)

> You can edit `init_vmsketch_bfrt.py` to adjust MAC/port mappings and sketch parameters.

---

## C. Generate Traffic & Verify

1. **Connect hosts/testers** to the switch ports you programmed.
2. Send traffic (e.g., `ping`, `iperf3`, or a packet generator).
3. **Inspect sketch state** with BFRT shell:

```bash
$SDE/run_bfshell.sh
bfrt> show
action_profile>  # explore tables
bfrt> bfrt.<your_prog>.<pipe>.register_name.get(first=0, count=16)
# or use counters / digests as defined in your P4
```

> Replace `register_name` with your actual object names from `vmsketch_tna.p4`.

---

## Quick Reference (Tofino)

```bash
# 1) Environment
source /opt/bf-sde-<ver>/set_sde.bash

# 2) Build TNA P4
$SDE/tools/p4_build.sh vmsketch_tna.p4 -T tofino -o vmsketch

# 3) Start switchd with program
sudo -E $SDE/run_switchd.sh -p vmsketch -f /path/to/<platform>_conf.json

# 4) Initialize pipeline
$SDE/run_bfshell.sh -b init_vmsketch_bfrt.py

# 5) Send traffic & inspect
$SDE/run_bfshell.sh
bfrt> bfrt.vmsketch.pipe.register_name.get(first=0, count=16)
```
