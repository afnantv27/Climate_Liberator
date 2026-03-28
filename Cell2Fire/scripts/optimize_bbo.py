#!/usr/bin/env python3
"""Calibrate BBO-enabled Cell2Fire run (H/F/B/E factors) against reference ROS raster."""
from __future__ import annotations

import subprocess
from pathlib import Path

import numpy as np
import rasterio as rio
from rasterio.enums import Resampling
from rasterio.warp import reproject
from skopt import gp_minimize
from skopt.space import Real

C2F_BIN = Path("/Users/afnan/Desktop/Climate-Liberator/Cell2Fire/Cell2Fire")
DATA_DIR = Path("/Users/afnan/Desktop/Climate-Liberator/data/ScottAndBurgan/Clinge")
OUTPUT_DIR = DATA_DIR / "simOuts"
TARGET_RASTER = Path("/Users/afnan/Downloads/ROS.tif")

BASE_CMD = [
    str(C2F_BIN),
    "--sim", "S",
    "--input-instance-folder", str(DATA_DIR),
    "--output-folder", str(OUTPUT_DIR),
    "--nsims", "1",
    "--nthreads", "7",
    "--seed", "123",
    "--weather", "rows",
    "--Weather-Period-Length", "30",
    "--Fire-Period-Length", "5",
    "--ignitions",
    "--fmc", "66",
    "--scenario", "3",
    "--ROS-Threshold", "0.25",
    "--bbo",
    "--grids",
    "--out-ros",
    "--output-messages",
]

ROS_ASC = OUTPUT_DIR / "RateOfSpread" / "ROSFile1.asc"


def rms_error(sim_path: Path, target_path: Path) -> float:
    with rio.open(sim_path) as sim_ds:
        sim = sim_ds.read(1, masked=True)
        sim_transform = sim_ds.transform
        sim_crs = sim_ds.crs

    with rio.open(target_path) as target_ds:
        target = target_ds.read(1, masked=True)
        target_transform = target_ds.transform
        target_crs = target_ds.crs

    if sim_crs is None and target_crs is not None:
        sim_crs = target_crs
    if target_crs is None and sim_crs is not None:
        target_crs = sim_crs

    if (
        sim.shape == target.shape
        and sim_transform == target_transform
        and (sim_crs == target_crs or sim_crs is None or target_crs is None)
    ):
        target_resampled = target.astype(np.float32, copy=False)
    else:
        target_resampled = np.empty(sim.shape, dtype=np.float32)
        reproject(
            source=target,
            destination=target_resampled,
            src_transform=target_transform,
            src_crs=target_crs,
            dst_transform=sim_transform,
            dst_crs=sim_crs,
            resampling=Resampling.bilinear,
        )

    diff = sim - target_resampled
    return float(np.sqrt(np.nanmean(np.square(diff))))


def run_cell2fire(h: float, f: float, b: float, e: float) -> float:
    cmd = BASE_CMD + [
        "--HFactor", f"{h:.4f}",
        "--FFactor", f"{f:.4f}",
        "--BFactor", f"{b:.4f}",
        "--EFactor", f"{e:.4f}",
    ]
    completed = subprocess.run(cmd, capture_output=True, text=True)
    if completed.returncode != 0:
        raise RuntimeError(
            f"Cell2Fire failed\nSTDOUT:\n{completed.stdout}\nSTDERR:\n{completed.stderr}"
        )
    if not ROS_ASC.exists():
        raise FileNotFoundError(f"Expected ROS output not found: {ROS_ASC}")
    return rms_error(ROS_ASC, TARGET_RASTER)


def main():
    bounds = [
        Real(0.2, 1.5, name="HFactor"),
        Real(0.2, 1.5, name="FFactor"),
        Real(0.2, 1.5, name="BFactor"),
        Real(0.2, 1.5, name="EFactor"),
    ]

    result = gp_minimize(
        func=lambda x: run_cell2fire(*x),
        dimensions=bounds,
        n_calls=25,
        n_initial_points=8,
        acq_func="EI",
        random_state=42,
    )

    print("Best RMSE:", result.fun)
    print("Best factors (H, F, B, E):", result.x)


if __name__ == "__main__":
    main()
