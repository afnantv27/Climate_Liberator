# Climate Liberator

Climate Liberator is a macOS climate risk intelligence platform for company-scale hazard simulation, portfolio screening, forecast intelligence, and disclosure workflows. The current build is India-first, wildfire-led, and designed to scale into a broader company climate risk operating system.

## What This Repository Contains

This repository is no longer just a wildfire engine fork. It is the working codebase for the Climate Liberator product and its supporting build/data layers.

Core product surfaces:
- `Dashboard`: the main launcher for the platform
- `Portfolio Intelligence`: company, site, and imported exposure screening
- `Climate Simulation`: wildfire simulation and evidence generation
- `Forecast Intelligence`: weather, seasonal, subseasonal, and air-quality intelligence
- `TCFD Dashboard`: review, approval, and board-pack workflow
- `Executive Overview`: management-facing summary of promoted evidence

## Current Product Capabilities

### Climate Simulation
- Wildfire simulation workflow with run configuration import/export
- Output review, evidence packaging, and artifact handling
- India preparedness and operations-console style execution
- Underlying wildfire engine support from the Cell2Fire-based code in this repository

### Portfolio Intelligence
- India-first portfolio and site screening
- Imported OED portfolio intake and canonical exposure persistence
- OED-style export for interoperability
- Risk concentration and nearby asset/site context

### Forecast Intelligence
- Short-term, subseasonal, and seasonal forecast support
- Air-quality outlook support
- Processed feed priority with live fallback where appropriate
- Trust, freshness, source, and evidence-promotion controls

### Disclosure Workflow
- Scenario library and package review workflow
- Threshold-breach actions
- Approval evidence and review history
- Board-pack export
- Quantitative financial-effects proxy support

## Repository Structure

Top-level layout:

```text
ClimateLiberatorApp/    macOS application, tests, assets, UI, stores, services
Cell2Fire/              underlying wildfire engine and native simulation code
data/                   sample and prepared data inputs
docs/                   architecture, optimization, QA, and product planning
container/              container build assets
test/                   engine-side tests and fixtures
.github/workflows/      CI workflows inherited and evolving with the project
```

Important app paths:
- App project:
  - `ClimateLiberatorApp/ClimateLiberator/ClimateLiberator.xcodeproj`
- Main app source:
  - `ClimateLiberatorApp/ClimateLiberator/ClimateLiberator`

## Architecture Direction

Climate Liberator is being built as a layered system:

1. `App layer`
   - macOS-native product surfaces for operations, portfolio, forecast, and disclosure
2. `Build/data layer`
   - typed contracts, manifests, validators, portfolio feeds, and forecast artifacts
3. `Engine/provider layer`
   - wildfire engine, processed forecast feeds, and external data/provider integration

The codebase is actively being refactored toward:
- stronger SOLID boundaries
- smaller service-oriented modules
- artifact-first workflows
- better scaling for future hazards and frameworks

## Getting Started

### macOS app

Open the Xcode project:

```bash
open /Users/afnan/Desktop/Climate-Liberator/ClimateLiberatorApp/ClimateLiberator/ClimateLiberator.xcodeproj
```

Or build from the command line:

```bash
xcodebuild \
  -project /Users/afnan/Desktop/Climate-Liberator/ClimateLiberatorApp/ClimateLiberator/ClimateLiberator.xcodeproj \
  -scheme ClimateLiberator \
  -destination 'platform=macOS' \
  build
```

### Tests

App scheme tests:

```bash
xcodebuild \
  -project /Users/afnan/Desktop/Climate-Liberator/ClimateLiberatorApp/ClimateLiberator/ClimateLiberator.xcodeproj \
  -scheme ClimateLiberator \
  -destination 'platform=macOS' \
  test
```

Build/data validation suites:

```bash
/Users/afnan/Desktop/Build/engine-rewrite/tests/run_disclosure_milestone.sh
/Users/afnan/Desktop/Build/india-risk-data/tests/run_data_milestone.sh
/Users/afnan/Desktop/Build/engine-rewrite/tests/run_performance_validation.sh
```

## Standards and Interoperability

The product is being built to support structured climate risk workflows rather than only raw hazard runs.

Current and planned standards seams include:
- `OED`: structured exposure intake/export
- `TCFD / IFRS S2`: disclosure workflow foundation
- future adapter direction for broader reporting frameworks

## Current Status

The repository is in active product transition from an inherited wildfire simulation base into a full climate risk intelligence platform.

Already in place:
- renamed product and app structure
- separate dashboard/workspace model
- OED intake/export seam
- forecast intelligence window and processed-feed model
- TCFD review and board-pack workflow
- Xcode unit, performance, and UI smoke tests
- Obsidian second-brain documentation of architecture and decisions

Still evolving:
- deeper simulation orchestration extraction
- richer portfolio analytics and company hierarchy
- stronger artifact-first runtime pipeline
- broader framework support
- future multi-hazard expansion

## Heritage

This repository still contains the Cell2Fire-derived wildfire engine and related native tooling. That work remains important inside Climate Liberator, but the repository now represents a larger product system than the original simulator alone.

## Documentation

Primary local architecture and project memory live in:

- `docs/`
- `/Users/afnan/Documents/Obsidian Vault/Codex/Climate Liberator`

The Obsidian second brain tracks:
- system architecture
- engineering decisions
- build/data layer design
- testing and benchmark notes
- roadmap and connected graph views
