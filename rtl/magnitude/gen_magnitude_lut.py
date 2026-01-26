#!/usr/bin/env python3
import argparse
import math
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--width", type=int, default=8)
    parser.add_argument("--half-bits", type=int, default=5)
    parser.add_argument("--out", default="magnitude_lut.mem")
    args = parser.parse_args()

    width = args.width
    half_bits = args.half_bits
    addr_w = 2 * half_bits
    depth = 1 << addr_w
    shift = (2 * width) - half_bits
    out_path = Path(args.out)

    max_val = (1 << (2 * width)) - 1
    hex_digits = (2 * width + 3) // 4

    with out_path.open("w", encoding="ascii") as f:
        for addr in range(depth):
            gx_idx = addr >> half_bits
            gy_idx = addr & ((1 << half_bits) - 1)
            gx_sq = gx_idx << shift
            gy_sq = gy_idx << shift
            mag = int(round(math.sqrt(gx_sq + gy_sq)))
            if mag > max_val:
                mag = max_val
            f.write(f"{mag:0{hex_digits}x}\n")

if __name__ == "__main__":
    main()
