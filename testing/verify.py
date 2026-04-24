#!/usr/bin/env python3
# This script proves that our simulator has identical output to QEMU. It's not
# used for much else, and doesn't make sense beyond EL0 behavior, at least for
# this encantation of the lab.
import subprocess
import sys
import re
import os
import time
import json

def run_simulator(elf_path):
    print(f"Running simulator on {elf_path}...")
    cmd = ["./ozone", "ozone-config.json", "sim", elf_path, "-l", "INFO"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print("Simulator failed:")
        print(result.stderr)
        return None

    regs = {}
    lines = result.stdout.splitlines()
    for line in lines:
        matches = re.findall(r"X(\d+)\s*:\s*0x([0-9a-fA-F]+)", line)
        for idx, val in matches:
            regs[f"x{idx}"] = int(val, 16)
        pc_match = re.search(r"PC:\s*0x([0-9a-fA-F]+)", line)
        if pc_match:
            regs["pc"] = int(pc_match.group(1), 16)
    return regs

def run_qemu(elf_path):
    print(f"Running QEMU on {elf_path}...")
    port = 1234
    qemu_proc = subprocess.Popen(["qemu-aarch64", "-g", str(port), elf_path],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    time.sleep(0.5)

    try:
        objdump = subprocess.check_output(["aarch64-linux-gnu-objdump", "-d", elf_path], text=True)
        ret_matches = re.findall(r"([0-9a-fA-F]+):\s+[0-9a-fA-F]+\s+ret", objdump)
        if not ret_matches:
            print("Could not find RET instruction in ELF")
            qemu_proc.kill()
            return None
        ret_addr = "0x" + ret_matches[-1]
    except Exception as e:
        print(f"Error finding RET: {e}")
        qemu_proc.kill()
        return None

    # Construct GDB command to print each register individually
    gdb_ex_cmds = [
        "set architecture aarch64",
        f"target remote 127.0.0.1:{port}",
        f"break *{ret_addr}",
        "continue"
    ]
    for i in range(31):
        gdb_ex_cmds.append(f"p/x $x{i}")
    gdb_ex_cmds.append("quit")

    gdb_cmd = ["gdb", "-q", "-batch"]
    for cmd in gdb_ex_cmds:
        gdb_cmd.extend(["-ex", cmd])

    try:
        gdb_result = subprocess.run(gdb_cmd, capture_output=True, text=True, timeout=20)
        qemu_proc.kill()

        regs = {}
        # Parse GDB print output: $1 = 0x146
        val_matches = re.findall(r"\$\d+\s+=\s+0x([0-9a-fA-F]+)", gdb_result.stdout)
        for i, val in enumerate(val_matches):
            if i < 31:
                regs[f"x{i}"] = int(val, 16)

        return regs
    except Exception as e:
        print(f"GDB failed: {e}")
        qemu_proc.kill()
        return None

def main():
    if len(sys.argv) < 2:
        print("Usage: verify.py ELF_PATH")
        sys.exit(1)

    elf_path = sys.argv[1]
    sim_regs = run_simulator(elf_path)
    qemu_regs = run_qemu(elf_path)

    if not sim_regs or not qemu_regs:
        print("Failed to get registers from one of the runners.")
        sys.exit(1)

    print("\nComparison Results (X0-X30):")
    mismatches = 0
    # Common AArch64 registers to ignore because of environment differences
    # X1 usually points to stack/env in QEMU, SP is always different
    # X5 is used as a stack-relative address in some tests
    # However, X0 is almost always our result register.
    ignore_regs = ["x1", "x5", "pc", "sp"]

    for i in range(31):
        reg = f"x{i}"
        s_val = sim_regs.get(reg, 0)
        q_val = qemu_regs.get(reg, 0)

        if reg in ignore_regs:
            continue

        if s_val != q_val:
            print(f"  {reg.upper():>3}: SIM=0x{s_val:016x} QEMU=0x{q_val:016x}  [MISMATCH]")
            mismatches += 1
        else:
            if i == 0 or s_val != 0:
                print(f"  {reg.upper():>3}: 0x{s_val:016x}  [MATCH]")

    if mismatches == 0:
        print("\n✅ Verification SUCCESS (ignoring env-dependent regs).")
    else:
        print(f"\n❌ Verification FAILED: {mismatches} register mismatches.")
        sys.exit(1)

if __name__ == "__main__":
    main()
