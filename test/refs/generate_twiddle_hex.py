#!/usr/bin/env python3
"""Generate forward/inverse twiddle hex files for psi^k tables."""

from __future__ import annotations

import argparse
from pathlib import Path


def write_hex(path: Path, values: list[int]) -> None:
    path.write_text("".join(f"{value:08x}\n" for value in values), encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--n", type=int, required=True)
    parser.add_argument("--q", type=int, required=True)
    parser.add_argument("--psi", type=int, required=True)
    parser.add_argument("--forward-out", type=Path, required=True)
    parser.add_argument("--inverse-out", type=Path, required=True)
    args = parser.parse_args()

    forward = [pow(args.psi, k, args.q) for k in range(args.n)]
    psi_inv = pow(args.psi, args.q - 2, args.q)
    inverse = [pow(psi_inv, k, args.q) for k in range(args.n)]

    write_hex(args.forward_out, forward)
    write_hex(args.inverse_out, inverse)


if __name__ == "__main__":
    main()
