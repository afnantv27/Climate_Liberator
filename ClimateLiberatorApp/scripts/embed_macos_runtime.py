#!/usr/bin/env python3
"""Copy the verified CLI and all non-system Mach-O dependencies into an app."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def dependencies(binary):
    return [line.strip().split(" (compatibility version")[0]
            for line in run("/usr/bin/otool", "-L", str(binary)).splitlines()[1:]]


def embed(app, engine, source):
    frameworks = app / "Contents/Frameworks"
    helpers = app / "Contents/Helpers"
    frameworks.mkdir(parents=True, exist_ok=True)
    helpers.mkdir(parents=True, exist_ok=True)
    helper = helpers / "Cell2Fire"
    shutil.copy2(engine, helper)
    engine_resources = app / "Contents/Resources/Engine"
    tools = engine_resources / "tools/fuel_models"
    tools.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / "tools/fuel_models/scott_burgan_table7.csv", tools)
    shutil.copy2(source / "../spain_lookup_table.csv", engine_resources)
    # Clean only the old generated resource layout; Helpers must contain signed code.
    (helpers / "spain_lookup_table.csv").unlink(missing_ok=True)
    if (helpers / "tools").is_dir():
        shutil.rmtree(helpers / "tools")
    license_dir = app / "Contents/Resources/Licenses"
    license_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / "../LICENSE", license_dir / "Cell2Fire-GPL-3.0.txt")
    pending = [*sorted((app / "Contents/MacOS").iterdir()), helper]
    copied = {}
    modified = []
    while pending:
        binary = pending.pop()
        for dependency in dependencies(binary):
            if dependency.startswith(("/usr/lib/", "/System/Library/")):
                continue
            if dependency.startswith(("@loader_path/", "@executable_path/", "@rpath/")):
                # A previous build phase may have already embedded this dependency.
                name = Path(dependency).name
                if (frameworks / name).exists() or (app / "Contents/MacOS" / name).exists():
                    continue
                raise RuntimeError(f"Unresolved relative dependency {dependency} in {binary}")
            original = Path(dependency).resolve(strict=True)
            if original == binary.resolve():
                continue
            name = original.name
            if name in copied and copied[name] != original:
                raise RuntimeError(f"Conflicting dylib names: {name}")
            destination = frameworks / name
            if name not in copied:
                copied[name] = original
                shutil.copy2(original, destination)
                os.chmod(destination, 0o755)
                run("/usr/bin/install_name_tool", "-id", f"@rpath/{name}", str(destination))
                pending.append(destination)
                # Homebrew formula licenses accompany redistributed native libraries.
                license_root = original.parent.parent
                for pattern in ("LICENSE*", "COPYING*", "COPYRIGHT*"):
                    for license_file in license_root.glob(pattern):
                        if license_file.is_file():
                            shutil.copy2(license_file, license_dir / f"{license_root.parent.name}-{license_file.name}")
            relative = f"@loader_path/{name}" if binary.parent == frameworks else f"@loader_path/../Frameworks/{name}"
            run("/usr/bin/install_name_tool", "-change", dependency, relative, str(binary))
        modified.append(binary)
    identity = os.environ.get("EXPANDED_CODE_SIGN_IDENTITY") or "-"
    for binary in modified:
        # Xcode signs the main app after this phase. Nested code must be signed first.
        if binary.parent != app / "Contents/MacOS" or binary.suffix == ".dylib":
            run("/usr/bin/codesign", "--force", "--sign", identity, "--timestamp=none", str(binary))
    for binary in modified:
        bad = [dep for dep in dependencies(binary)
               if dep.startswith("/") and not dep.startswith(("/usr/lib/", "/System/Library/"))]
        if bad:
            raise RuntimeError(f"Nonportable dependencies in {binary}: {bad}")
    print(f"Embedded engine and {len(copied)} native libraries in {app}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("engine", type=Path)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    embed(args.app, args.engine, args.source)
