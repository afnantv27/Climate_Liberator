# Climate Liberator Enterprise Readiness Plan

## Scope

This document defines the implementation path for taking Climate Liberator from a strong single-operator macOS application to an enterprise-grade climate risk platform with a service-backed control plane.

The target operating model is:

- `private cloud / on-prem`
- `mid-enterprise` first
- macOS app retained as the analyst client
- service-backed system of record for portfolio, forecast, simulation, artifact, and disclosure operations

## Current Baseline

Measured local baselines as of `2026-04-03`:

- app launch average: `0.447s`
- TCFD discovery across `300` bundles: `0.030s` first pass, `0.031s` second pass
- nearby portfolio lookup across `50k` assets: `0.104s`
- grouped portfolio rollup across `50k` assets: `2.112s`
- forecast feed loading: `0.071s`

Primary enterprise blockers:

- no service-backed uptime boundary yet
- no live `p50 / p95 / p99` telemetry
- grouped portfolio rollups remain the main scale hotspot
- disclosure performance coverage is stronger on discovery than on richer review interactions
- native `S` engine is valid as a preview runtime but not yet enterprise-operational
- no HA/DR proof, queue-worker SLOs, or proving window

## Enterprise Target

The explicit target is to raise Climate Liberator to `9/10` in:

- architectural scalability
- latency profile
- data/query scalability
- simulation scalability
- enterprise SLA / SLO maturity

## Service Boundaries

Climate Liberator should converge on these service boundaries:

- `Gateway / Auth`
- `Portfolio Query Service`
- `Forecast Artifact Service`
- `Simulation Orchestrator`
- `Artifact Registry / Store`
- `Disclosure / Evidence Service`
- `Observability / Audit Plane`

The macOS app remains:

- the operator-facing shell
- a cached enterprise client
- not the system of record

## Stable Contracts

The enterprise control plane should standardize on these simulation/runtime contracts:

- `RunConfig`
- `PreparedInstanceSummary`
- `OutputManifest`
- `ArtifactIndex`
- `RunArtifact`

The app should progressively stop treating local paths and console output as the durable contract.

## SLO / SLA Targets

Availability targets:

- platform availability: `99.9%` monthly
- interactive API availability: `99.9%`
- simulation orchestration availability: `99.5%`
- artifact retrieval availability: `99.9%`
- artifact durability: `99.99%`
- RPO: `<= 15 minutes`
- RTO: `<= 4 hours`

Latency targets:

- dashboard summary: `<= 0.8s p95`, `<= 1.5s p99`
- nearby asset lookup at `100k` assets: `<= 0.25s p95`, `<= 0.6s p99`
- grouped portfolio rollup at `100k` assets: `<= 1.0s p95`, `<= 2.5s p99`
- disclosure bundle discovery at `1,000` bundles: `<= 0.5s p95`, `<= 1.0s p99`
- forecast artifact / trust retrieval: `<= 0.3s p95`, `<= 0.8s p99`
- simulation job submission acknowledgment: `<= 1.0s p95`
- simulation queue start under nominal load: `<= 30s p95`
- artifact registration after worker completion: `<= 10s p95`

Reference capacity target:

- `50` concurrent analysts
- `200` sustained interactive requests/minute
- `600` burst interactive requests/minute
- `8` active simulation worker slots
- `20` simulation submissions/hour sustained
- `100` queued jobs without orchestration degradation
- `100k` committed assets, `250k` validated stretch
- `1,000` committed disclosure bundles, `2,000` validated stretch
- `500` committed forecast locations

## Phase Plan

### Phase 1: SLI / SLO Foundation and Observability

ETA: `2–3 weeks`

- define the SLI dictionary
- instrument critical workflows
- emit `p50 / p95 / p99`-ready latency samples
- define monthly SLA reporting
- define the error-budget policy

### Phase 2: Control-Plane Extraction

ETA: `4–5 weeks`

- extract portfolio, forecast artifact, disclosure, and simulation submission APIs
- preserve current app workflows above the new seams
- establish artifact registry semantics and service identities

### Phase 3: Data / Query and Artifact Scale Hardening

ETA: `4–5 weeks`

- redesign grouped portfolio rollups
- add hierarchy-aware summary artifacts
- add `100k` and `250k` asset fixtures
- add `1,000` and `2,000` bundle disclosure tests
- benchmark artifact retrieval explicitly

### Phase 4: Engine and Job Orchestration Hardening

ETA: `4–5 weeks`

- add native `S` parity harness
- benchmark engine throughput and memory
- introduce queue / worker / status lifecycle
- add artifact completeness validation
- make `nthreads` real
- support cancellation, timeout, and structured failure states

### Phase 5: Security, HA, DR, and Runbooks

ETA: `3–4 weeks`

- complete the audit trail
- verify backup / restore
- define failover and rollback procedures
- add alerting and incident runbooks
- ship a private-cloud / on-prem deployment guide

### Phase 6: 30-Day Proving Period

ETA: `3–4 weeks`

- run a production-like soak
- validate SLO conformance
- verify no red-grade breach
- finalize the external SLA language

## Total ETA

- deployment-ready enterprise baseline: `17–20 weeks`
- credible `9/10` readiness across all five categories after the proving window: `20–24 weeks`

## Implementation Status in the App Repo

This repository now includes:

- a local enterprise control-plane façade
- an SLO catalog and capacity target catalog
- enterprise observability latency recording
- a local artifact registry for simulation runs
- a simulation-engine wrapper that records enterprise telemetry and artifact registration

This is the foundation layer, not the final enterprise deployment.
