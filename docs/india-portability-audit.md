# India Portability and Optimization Audit

Date: 2026-09-10. Scope: the macOS product and its packaged S execution path,
not a claim that every source file or the external rewrite lab is fully audited.

## Direction

Follow `product-architecture.md`: prove the India-first hazard -> exposure ->
vulnerability -> financial -> disclosure slice before adding distributed-service
abstractions. Keep original engine attribution. Do not equate additional layers,
lines of code or local benchmarks with enterprise readiness.

## Implemented

| Area | Change and reason |
|---|---|
| App shell | Removed speculative enterprise-readiness panels and local control-plane facade initialization. Existing proposals/contracts remain reversible, but are not represented as a deployed service. |
| Launch | Removed the mandatory five-second wait and forced fullscreen. Artwork is a short nonblocking overlay respecting reduced motion. |
| Engine packaging | Build the S CLI from repo source; bundle helper, fuel tables and recursive non-system native dependencies. Incremental native compilation tracks compiler flags and source/header changes instead of a one-hour freshness shortcut. |
| Data paths | Active Swift sources no longer embed developer `/Users/...`, `Desktop/Build` or `C2F-W` paths. Default engine resolution follows the app bundle. Explicit user overrides are preserved. |
| India onboarding | Install a versioned, writable synthetic starter from `StarterData.bundle`; Bengaluru map/forecast defaults; INR screening example. No private Build datasets copied into Git. |
| Data import | Settings imports approved SQLite data using a consistent backup, schema/integrity validation, and previous-version retention. Committed WAL contents are included. Readers handle newly initialized WAL stores. |
| Nearby queries | Indexed bounding box followed by exact spherical distance; retain only the nearest 25. Removed an arbitrary SQL limit that could exclude the closest asset. Validate finite coordinates/radius. |
| Portfolio summaries | Materialize the latest wildfire assessment per existing building once per cold snapshot. Read counts and hierarchy summaries in one transaction; historical assessments no longer double-count assets. |
| Cache safety | Include database/WAL/journal revisions; reject stale writes, bound retained entries, invalidate old cache format and discard out-of-order location responses. |
| Forecasts | Bounded version-aware JSON cache. Require current timestamps and location proximity (25 km configured default); reject synthetic feeds. Preserve real provider/source/location identity. |
| Forecast history | A main-thread sample caught launch blocked on a cloud-backed Documents directory. Serialized background evidence I/O removes that launch/interaction dependency without deleting historical evidence. |

## Verified Measurements

Machine: Apple Silicon MacBook Air, macOS 26.5.1; Xcode 26.3. Unit/performance
configuration: Debug, nonparallel test execution. Final run: 2026-09-10. These are local microbenchmarks
with synthetic fixtures, not production telemetry or a comparison to an identically
configured historical baseline.

| Check | Result | Interpretation |
|---|---|---|
| App unit/performance suite | 54 tests, 0 failures | Includes financial/reporting prototypes, OED intake and the new portability regressions. |
| UI smoke suite | 4 tests, 0 failures | Dashboard, Climate Simulation, Forecast Intelligence and Disclosure Review opening paths. Not complete workflow/visual coverage. |
| Nearby lookup, 100,000 assets + assessments | p50 1.434 ms; p95 1.546 ms, 20 samples | Indexed 750 m search near Bengaluru; not an India-wide search or concurrent-analyst load test. |
| Portfolio summary, same fixture | Cold 322.929 ms; warm 0.274 ms | One cold and one cached observation, not p95 or p99. Database construction excluded. |
| Relocated Release app | Passed native dependency and seed-hash checks; S run produced a 12 x 12 ROS raster | App copied to a path containing spaces, fresh HOME, minimal PATH; no non-system absolute dylib dependencies. |
| Repeat packaged fixture runs | Identical ROS SHA-256: `f0cbfce2b599fab98cee2c5954c90985070ec41ca4b1880dec94196fac5a8dd1` | Packaging/determinism smoke only; a tiny fixture is not a scaling or scientific calibration result. |
| Whitespace and runtime-path audit | `git diff --check` clean; no developer absolute paths in active Swift sources | Not a blanket claim about historical docs or optional tool paths. |

The relocation check ran the packaged helper, not a GUI test on a second physical
Mac. Core app initialization was exercised by hosted XCTest. UI smoke tests run
on the development Mac; the dashboard action spacing and accessibility selectors
were corrected after those tests exposed failures. Local build activity may
affect benchmark timings; these are not dedicated-hardware capacity measurements.

## Reproduce

From the repository root:

```sh
xcodebuild -project ClimateLiberatorApp/ClimateLiberator/ClimateLiberator.xcodeproj \
  -scheme ClimateLiberator -destination 'platform=macOS' \
  -parallel-testing-enabled NO test
bash scripts/package_macos.sh
```

`IndiaPortabilityTests.testHundredThousandAssetLookupAndRollupBenchmark` prints
the raw `INDIA_BENCHMARK` values. The seed generator and schema are versioned;
`scripts/verify_portable_app.py` validates a supplied Release `.app` independently.
Packages remain ignored local build outputs, not automatically uploaded releases.

## Data Ownership and Scope

Default data library: `~/Library/Application Support/ClimateLiberator/`.
Original scenario/disclosure/evidence locations remain where their existing
stores expect them, including `~/Documents/ClimateLiberator/`. Settings exposes
the data library and seed OED example. User-selected output roots remain valid.
Quit the app and database writers before backup/migration; copy the full data
library, evidence directory and custom output roots, not just a live `.db` file.

The starter contains 12 fictional building records, a 12 x 12 artificial grass
study and an example INR screening CSV. It does not provide national building
stock, current weather, surveyed fuels, insured TIV, catastrophe calibration or
permission to redistribute third-party data. The current India OED-style export
can derive proxy values from area; these must not be mistaken for insured values.

## Remaining Gates

- Test the installer on a clean second Mac; sign/notarize releases and document
  third-party redistribution obligations before public distribution. macOS 26.2+
  and compatible architecture are required; only Apple Silicon was exercised.
- Full map reprojection/KMZ and Earth Engine preparation are not self-contained:
  they require optional GDAL/configuration. Maps and live forecasts need network.
- Native rewrite/embedded output parity and India-specific fire/vulnerability
  calibration remain unresolved. The packaged legacy-derived CLI stays default.
- Portfolio numbers are a latest-assessment overview, not a scenario-normalized
  actuarial aggregation. Complete financial OED contracts and insured-value
  validation remain separate acceptance gates.
- SQLite is a local single-user library, not a multi-tenant concurrent service.
  Import during active simulation/database writing is not an approved workflow.
  External file mutation is detected by revisions, not a distributed transaction.
- There is no proved uptime boundary, HA/DR, production p95/p99, multi-analyst
  load/soak evidence or enforceable SLA. No 9/10 enterprise certification is claimed.
- Cloud-backed evidence files may still be unavailable, but now load asynchronously.
  A broader bounded/background disclosure hydration audit remains worthwhile.
- Legacy large views, engine internals and the external Build workbench retain
  further refactoring/scientific work. This pass avoids adding another service layer.
