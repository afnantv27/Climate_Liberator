# ClimateScan Production Optimization Roadmap

## Objective
Turn ClimateScan from a structurally improved product into a production-grade platform by reducing oversized ownership boundaries, moving runtime work onto durable service layers, and tightening performance validation.

## Current Hotspots
- `ContentView.swift`
  - still owns too much simulation state and runtime orchestration
- `TCFDReviewStore.swift`
  - workflow logic is cleaner, but orchestration is still broad
- `IndiaRiskStore.swift`
  - structurally improved, but analytics depth and query tuning are limited
- `ForecastIntelligenceStore.swift`
  - still mixes feed orchestration, trust state, and evidence promotion
- Performance verification
  - not enough profiling-oriented checks on heavy workflows

## Phase 1: View-Layer Containment
Goal: make top-level views route and compose, not perform pipeline work.

### Completed
- Workspace shell extracted from `ContentView`
- Climate simulation workspace composition extracted from `ContentView`
- Simulation artifact packaging extracted to `SimulationArtifactService`
- Output-tree orchestration extracted into `SimulationOutputStore` + `SimulationOutputTreeService`
- Run-config import/export and review-root resolution extracted into simulation services

### Next
- Extract simulation execution coordination from `ContentView`
- Extract map/overlay state management from `ContentView`
- Keep `ContentView` as router + lifecycle only

## Phase 2: Service-Layer Separation
Goal: separate orchestration, persistence, export, and provider concerns.

### Completed
- `IndiaRiskStore` split behind repository/export/demo services
- `TCFDReviewStore` split behind discovery/persistence/export services
- `ForecastIntelligenceStore` split behind feed/live/snapshot services
- `ForecastIntelligenceStore` split further behind metric-building and evidence-promotion services

### Next
- Split `ForecastIntelligenceStore` again:
  - processed-feed orchestration
  - trust/status derivation
  - evidence-promotion manager
- Split `TCFDReviewStore` further:
  - snapshot synchronizer
  - comparison evidence engine
  - metrics/threshold calculator

## Phase 3: Analytics and Query Depth
Goal: make portfolio and site intelligence credible under larger datasets.

### India risk
- Add repository-level query plans and indexes for frequent site lookup paths
- Add cached portfolio rollups for:
  - state concentration
  - scenario counts
  - latest assessment windows
- Move heavier portfolio summaries fully into Build-fed processed artifacts where possible

### Completed
- Nearby site lookups now use cache keys based on database path, radius, and rounded coordinates to avoid redundant SQLite fetches during repeated screening

### Forecast
- Prefer Build-processed feeds over app-derived state for all non-live horizons
- Promote warning overlays and provider trust summaries as first-class artifacts

## Phase 4: Artifact-First Runtime
Goal: make every major workflow reproducible and inspectable.

- Simulation runs
  - immutable `run_config.json`
  - deterministic artifact manifest
  - rerun-ready output package
- Forecast evidence
  - persisted evidence snapshot
  - explicit promotion path to executive/disclosure
- Disclosure
  - append-only review history
  - explicit export artifacts

## Phase 5: Performance Validation
Goal: optimize using measured hotspots, not intuition.

### Required checks
- App build and disclosure suite
- India data suite
- Forecast processed-feed validation
- Profiling-oriented checks for:
  - TCFD discovery duration
  - India nearby-site lookup latency
  - output-tree load latency
  - overlay rebuild frequency

### Added
- `Build/engine-rewrite/tests/validate_tcfd_discovery_performance.py`
- `Build/india-risk-data/tests/validate_query_performance.py`
- `Build/environment-risk-data/tests/validate_forecast_feed_performance.py`
- `Build/engine-rewrite/tests/run_performance_validation.sh`

### Target metrics
- no main-thread blocking for discovery, DB lookup, or forecast fetch
- bounded refresh behavior for repeated reloads
- stable navigation under large package counts

## Immediate Implementation Order
1. Finish reducing `ContentView` to router/lifecycle only
2. Split forecast orchestration from evidence promotion
3. Strengthen India repository indexing and cached summaries
4. Add profiling-oriented validation for heavy paths
5. Move more portfolio/forecast state to Build artifacts

## Standard
Every refactor should improve at least one of:
- single-responsibility clarity
- dependency inversion
- testability
- artifact durability
- measured runtime responsiveness
