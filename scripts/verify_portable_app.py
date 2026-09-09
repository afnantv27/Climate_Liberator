#!/usr/bin/env python3
"""Verify copied macOS runtime closure and run the synthetic India S fixture."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import time


def verify(app):
    with tempfile.TemporaryDirectory(prefix="climate relocated ") as temp:
        root = Path(temp)
        relocated = root / "Climate Liberator.app"
        shutil.copytree(app, relocated, symlinks=True)
        frameworks = relocated / "Contents/Frameworks"
        binary = relocated / "Contents/Helpers/Cell2Fire"
        for library in [*frameworks.glob("*.dylib"), *relocated.joinpath("Contents/MacOS").iterdir(), binary]:
            report = subprocess.check_output(["/usr/bin/otool", "-L", str(library)], text=True)
            for line in report.splitlines()[1:]:
                dependency = line.strip().split(" (compatibility version")[0]
                if dependency.startswith("/"):
                    assert dependency.startswith(("/usr/lib/", "/System/Library/")), (library, dependency)
                elif dependency.startswith("@loader_path/"):
                    assert (library.parent / dependency.removeprefix("@loader_path/")).exists(), dependency
                elif dependency.startswith("@rpath/"):
                    name = Path(dependency).name
                    assert (frameworks / name).exists() or (library.parent / name).exists(), dependency
                else:
                    raise AssertionError(f"Unexpected library reference: {dependency}")
        seed = relocated / "Contents/Resources/StarterData.bundle"
        manifest = json.loads((seed / "manifest.json").read_text())
        assert manifest["synthetic"] is True
        for name, digest in manifest["files_sha256"].items():
            assert hashlib.sha256((seed / name).read_bytes()).hexdigest() == digest, name
        study = root / "India input"
        shutil.copytree(seed / "Studies/India-Demo-S", study)
        outputs = root / "run outputs"
        outputs.mkdir()
        home = root / "fresh home"
        home.mkdir()
        command = [str(binary), "--sim", "S", "--input-instance-folder", str(study),
                   "--output-folder", str(outputs), "--nsims", "1", "--nthreads", "1", "--seed", "123",
                   "--out-ros", "--grids", "--final-grid", "--output-messages", "--ignitions", "--weather", "rows"]
        started = time.monotonic()
        result = subprocess.run(command, cwd=relocated / "Contents/Resources/Engine", env={"HOME": str(home), "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"},
                                capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise RuntimeError(result.stdout[-4000:] + result.stderr[-4000:])
        ros = outputs / "RateOfSpread/ROSFile1.asc"
        assert ros.is_file(), f"Missing ROS raster: {result.stdout[-3000:]}"
        lines = ros.read_text().splitlines()
        assert int(lines[0].split()[-1]) == 12 and int(lines[1].split()[-1]) == 12
        print(json.dumps({"copied_app": "verified", "fixture": "synthetic India 12x12 S", "engine_elapsed_seconds": round(time.monotonic()-started, 4),
                          "ros_sha256": hashlib.sha256(ros.read_bytes()).hexdigest(), "external_non_system_dylibs": 0}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    verify(parser.parse_args().app.resolve())
