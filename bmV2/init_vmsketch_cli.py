import random

L = 5000
W = 65536

print("# Example L2 entries (edit for your MACs/ports)")
print("table_add l2_fwd set_out_port 00:00:00:00:00:02 => 1")
print("table_add l2_fwd set_out_port 00:00:00:00:00:03 => 2")
print()

for i in range(W):         # C[:] = 0xFFFF
    print(f"register_write regC {i} 65535")

rng = random.Random(0xC0FFEE)
for i in range(L):         # A[:] = random 32-bit
    print(f"register_write regA {i} {rng.getrandbits(32)}")
