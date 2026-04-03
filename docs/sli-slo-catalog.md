# Climate Liberator SLI / SLO Catalog

## Measurement Classes

Climate Liberator should emit telemetry in these classes:

- `interactiveRequest`
- `asyncJobSubmission`
- `asyncJobQueueStart`
- `asyncJobCompletion`
- `artifactFetch`
- `artifactGeneration`

These classes are intentionally reusable across:

- dashboard
- portfolio
- forecast
- simulation
- disclosure
- artifact registry
- platform services

## Surface-Level Objectives

### Dashboard

- `interactiveRequest p95 <= 800 ms`
- `interactiveRequest p99 <= 1,500 ms`

### Portfolio

- nearby lookup at `100k` assets:
  - `interactiveRequest p95 <= 250 ms`
  - `interactiveRequest p99 <= 600 ms`
- grouped rollup at `100k` assets:
  - `artifactFetch p95 <= 1,000 ms`
  - `artifactFetch p99 <= 2,500 ms`

### Forecast

- processed artifact / trust retrieval:
  - `artifactFetch p95 <= 300 ms`
  - `artifactFetch p99 <= 800 ms`

### Disclosure

- bundle discovery at `1,000` bundles:
  - `artifactFetch p95 <= 500 ms`
  - `artifactFetch p99 <= 1,000 ms`

### Simulation

- submission acknowledgment:
  - `asyncJobSubmission p95 <= 1,000 ms`
- queue start:
  - `asyncJobQueueStart p95 <= 30,000 ms`
- artifact registration after worker completion:
  - `artifactGeneration p95 <= 10,000 ms`

## Availability Objectives

- platform: `99.9%`
- interactive API: `99.9%`
- simulation orchestration: `99.5%`
- artifact retrieval: `99.9%`
- artifact durability: `99.99%`

## Capacity Model

Reference deployment:

- `50` concurrent analysts
- `200` sustained interactive requests/minute
- `600` burst interactive requests/minute
- `8` active simulation worker slots
- `20` simulation submissions/hour sustained
- `100` queued jobs without orchestration degradation
- `100k` committed assets, `250k` validated stretch
- `1,000` committed bundles, `2,000` validated stretch
- `500` committed forecast locations

## Reporting Requirements

Monthly enterprise reporting should include:

- sample count by surface and metric class
- success rate
- `p50 / p95 / p99`
- breached objective count
- queue backlog distribution
- artifact registration failure rate
- top regression surfaces

## Current Implementation Note

The app repo currently records enterprise latency samples and artifact registry entries locally. This is a foundation step for:

- control-plane extraction
- service-level reporting
- workload benchmarking
- proving-window readiness
