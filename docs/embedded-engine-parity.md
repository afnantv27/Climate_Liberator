# Embedded Cell2Fire Engine — Parity Status

Last tested: 2026-06-23

## Summary

The embedded in-process Cell2Fire engine (`Cell2Fire/cell2fire_api.{h,cpp}`,
adapter in `ClimateLiberatorApp/.../Cell2FireEngine/`) **builds and links**
cleanly under the Xcode toolchain, but it is **not yet at output parity** with
the legacy subprocess engine (the CLI `Cell2Fire` binary), which remains the
verified ground truth.

**Therefore the app defaults to the legacy engine.** The embedded engine is
opt-in and labeled "experimental — not at CLI parity" in the engine picker.

## How parity was tested

Same input, same seed, single thread, identical parameters:

```
input:  data/ScottAndBurgan/Clinge
sim:    S (Scott & Burgan)
nsims:  1   seed: 123   nthreads: 1
toggles: --out-ros --grids --final-grid
```

- CLI:      `Cell2Fire/Cell2Fire --input-instance-folder … --output-folder /tmp/cli_out …`
- Embedded: a small C harness calling the `cell2fire_api` lifecycle
  (`c2f_config_* → c2f_sim_create → c2f_sim_run_all`), output to `/tmp/emb_out`.

## Result: FAIL

| Metric | CLI (ground truth) | Embedded | Match |
|---|---|---|---|
| Fire periods simulated | 14 | 4 | no |
| Burnt cells (final scar) | 4188 | 3219 | no (~23% under) |
| `RateOfSpread/ROSFile1.asc` | (md5 A) | (md5 B) | no |
| `c2f_sim_get_summary` burnt | 4188 | 0 | no |

## Known bugs to fix before the embedded engine can be promoted

### Bug 1 — fire stops early (run setup divergence)
`cell2fire_api.cpp::c2f_sim_run_all` reimplements the CLI's simulation loop and
diverges from `Cell2Fire.cpp::main`. The fire halts after 4 periods instead of
14, so it under-burns. Most likely cause: data-derived parameters are not
populated the way the CLI populates them — e.g. `NWeatherFiles` defaults to `1`
in `c2f_config_t` (see the "Mirror the defaults from parseArgs" block) but the
CLI counts the actual weather files in the instance folder. Audit every field
the CLI derives from the input folder and ensure `c2f_sim_create` sets them
identically.

### Bug 2 — `get_summary` returns zeros after `run_all`
`c2f_sim_run_all` runs each episode in a **thread-local copy**
(`Cell2Fire Forest = Forests[TID]`) and discards it, while `c2f_sim_get_summary`
reads `sim->forest` (the untouched primary instance). So the in-memory summary
is always empty after `run_all`. This is almost certainly why the simulation
summary table does not populate in the UI when the embedded engine is used.
Fix: have `run_all` write results back into `sim->forest` (or an aggregate),
or have the app read summaries from the step API (`reset`/`step`/`finalize`),
which operate on `sim->forest` directly.

## Reproducing

The throwaway harness used for this test is not committed (it lives in `/tmp`).
To re-run, build one against `ClimateLiberatorApp/build/lib/libcell2fire.a`
using `cell2fire_api.h`, run it and the CLI with the parameters above, then diff
`Grids/Grids1/` and `RateOfSpread/ROSFile1.asc` between the two output folders.
