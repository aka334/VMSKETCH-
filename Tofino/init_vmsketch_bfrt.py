# ~/init_vmsketch_bfrt.py
from random import Random
p4 = bfrt.vmsketch_tna
L, W, C_INIT = 4096, 65536, 0xFFFF

print("=== PORT TABLE ===")
bfrt.port.port.get(regex=True, print_ents=True)
DEVPORT_A = int(input("DEV_PORT for host A: "))
DEVPORT_B = int(input("DEV_PORT for host B: "))
MAC_A = "02:00:00:00:00:0a"
MAC_B = "02:00:00:00:00:0b"

# enable ports (ignore if already enabled)
try:
    bfrt.port.port_cfg.set(DEV_PORT=DEVPORT_A, port_enable=True)
    bfrt.port.port_cfg.set(DEV_PORT=DEVPORT_B, port_enable=True)
except Exception as e:
    print("port_cfg set skipped:", e)

l2 = p4.MyIngress.l2_fwd
l2.clear()
l2.add(key_fields={'hdr.ethernet.dstAddr': MAC_B},
       data_fields={'port': DEVPORT_B}, action='set_out')
l2.add(key_fields={'hdr.ethernet.dstAddr': MAC_A},
       data_fields={'port': DEVPORT_A}, action='set_out')

# initialize registers
regC = p4.regC
for i in range(W):
    regC.entry_mod(REGISTER_INDEX=i, f1=C_INIT)

regA = p4.regA
rng = Random(0xC0FFEE)
for i in range(L):
    regA.entry_mod(REGISTER_INDEX=i, f1=rng.getrandbits(32))

print("Initialized L2 + registers. ✅")
