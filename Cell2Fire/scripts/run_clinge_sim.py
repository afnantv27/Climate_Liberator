#!/usr/bin/env python3
"""
Utility runner for the Scott & Burgan Clinge dataset.

This script wraps the compiled Cell2Fire binary so you can trigger a
simulation against the `/Users/afnan/Desktop/Climate-Liberator/data/ScottAndBurgan/Clinge`
instance in a single command and always capture the Rate Of Spread (ROS)
output in a deterministic location.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run Cell2Fire for the Clinge Scott & Burgan instance "
        "and consolidate the ROS output into a single file."
    )
    parser.add_argument(
        "--binary",
        default="./Cell2Fire",
        help="Path to the compiled Cell2Fire executable.",
    )
    parser.add_argument(
        "--data",
        default="/Users/afnan/Desktop/Climate-Liberator/data/ScottAndBurgan/Clinge",
        help="Input instance folder containing fuels, weather, etc.",
    )
    parser.add_argument(
        "--output-folder",
        help="Optional override for the simulator output directory. "
        "Defaults to <data>/simOuts.",
    )
    parser.add_argument(
        "--ros-file",
        help="Path of the consolidated ROS grid to create or overwrite. "
        "Defaults to <output-folder>/ROS.asc.",
    )
    parser.add_argument("--nsims", type=int, default=1, help="Number of replications to run.")
    parser.add_argument("--sim", default="S", help="Simulator variant to use (S, K, C, P).")
    parser.add_argument("--nthreads", type=int, default=1, help="OpenMP thread count.")
    parser.add_argument("--seed", type=int, default=123, help="Base RNG seed.")
    parser.add_argument(
        "extra_args",
        nargs=argparse.REMAINDER,
        help="Additional CLI flags forwarded verbatim to Cell2Fire.",
    )
    args = parser.parse_args()

    data_path = Path(args.data).expanduser().resolve()
    if not data_path.exists():
        parser.error(f"Data folder does not exist: {data_path}")
    args.data_path = data_path

    if args.output_folder:
        args.output_path = Path(args.output_folder).expanduser().resolve()
    else:
        args.output_path = data_path / "simOuts"
    args.output_path.mkdir(parents=True, exist_ok=True)

    if args.ros_file:
        args.ros_path = Path(args.ros_file).expanduser().resolve()
    else:
        args.ros_path = args.output_path / "ROS.asc"
    args.ros_path.parent.mkdir(parents=True, exist_ok=True)

    binary_path = Path(args.binary).expanduser().resolve()
    if not binary_path.exists():
        parser.error(f"Binary does not exist: {binary_path}")
    args.binary_path = binary_path

    return args


def run_simulation(args: argparse.Namespace) -> None:
    cmd = [
        str(args.binary_path),
        "--sim",
        args.sim,
        "--input-instance-folder",
        str(args.data_path),
        "--output-folder",
        str(args.output_path),
        "--nsims",
        str(args.nsims),
        "--nthreads",
        str(args.nthreads),
        "--seed",
        str(args.seed),
        "--out-ros",
    ]
    if args.extra_args:
        cmd.extend(args.extra_args)

    print("Running:", " ".join(cmd))
    completed = subprocess.run(cmd, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"Simulation failed with exit code {completed.returncode}")


def consolidate_ros(output_path: Path, ros_path: Path) -> Path:
    ros_dir = output_path / "RateOfSpread"
    if not ros_dir.is_dir():
        raise FileNotFoundError(f"RateOfSpread folder not found: {ros_dir}")
    ros_candidates = sorted(ros_dir.glob("ROSFile*.asc"))
    if not ros_candidates:
        raise FileNotFoundError(f"No ROSFile*.asc outputs found inside {ros_dir}")

    # Pick the newest ROS grid and copy it into the requested location.
    newest = max(ros_candidates, key=lambda p: p.stat().st_mtime)
    shutil.copy2(newest, ros_path)
    print(f"Saved consolidated ROS grid to {ros_path} (source {newest.name})")
    return ros_path


def main() -> None:
    args = parse_args()
    try:
        run_simulation(args)
        consolidate_ros(args.output_path, args.ros_path)
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
