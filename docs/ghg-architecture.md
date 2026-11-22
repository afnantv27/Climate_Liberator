# GHG module architecture

Code: `ClimateLiberatorApp/ClimateLiberator/ClimateLiberator/GHGAccounting/`.
Dependencies point down only; nothing here imports the physical-risk core.

| Folder | Holds | Depends on |
|---|---|---|
| `Core/` | Gases, GWP sets, units, `EmissionFactor`, `EmissionCalculator`, storage paths and JSON | Foundation |
| `Factors/` | Seed library, online connectors, library store, API-key store | Core |
| `Boundary/` | Boundary polygon, area, place search | Core |
| `Inventory/` | GPC models, catalog, store, summary, report export, example inventory, unsaved-changes guard | Core, Factors, Boundary |
| `Decarbonization/` | Scenario models, measure catalog, engine, GPC baseline adapter; action plan models, suggestions and cost analysis | Core, Factors, Inventory (adapter only) |
| `Views/` | SwiftUI screens per pipeline step; `Components/` for shared cards, colours and formatting | all of the above |

## Rules

- Models and engines are `nonisolated` value types (the target defaults to
  MainActor); stores are `@MainActor ObservableObject`s and the only writers.
- Views change data through `GPCInventoryStore.mutateSelected`, so every edit
  is marked unsaved; nothing is written without the user choosing Save.
- Saved files stay readable: new fields are optional (e.g.
  `GPCInventory.scenarios`).
- Every default number carries a source or an assumption flag.

## Decarbonisation engine

```
inventory ──adapter──▶ ScenarioBaseline (ScenarioLine[])
                              │
scenario (measures, growth) ──▶ DecarbonizationEngine ──▶ ScenarioProjection
                              │                            (BAU, scenario, wedges per year)
              DecarbonizationMeasureCatalog (selectors + effects + sources)
```

- `ScenarioLine` is framework-neutral: source key, group key, energy carriers,
  grid flag, gases, kWh, tonnes.
- A measure = `SourceSelector` (key prefixes, carriers, grid flag) +
  `MeasureEffect` built from parameters. Ten effect types cover demand cuts,
  fuel switches, waste diversion, methane, clean supply, grid path, removals.
- The engine is pure and deterministic; tests pin the arithmetic.

## Adding corporate (GHG Protocol) later

1. Add `Corporate/` with the corporate inventory model and store.
2. Write `GHGProtocolScenarioBaselineAdapter`: one line per scope 1/2/3
   source; source keys such as `S1.stationary`, `S2.electricity`, `S3.1`;
   `electricitySourceKey` → `S2.electricity`.
3. Add corporate measures (process heat electrification, supplier engagement,
   material substitution, PPAs, fleet) to a second catalog, or tag existing
   measures with both key sets. Engine and views are reused unchanged.
4. Product-level (e.g. 3D-printing) calculators become activity data feeding
   scope 1–3 lines, not a separate engine.

## Links to the rest of the app (planned)

The GHG module stays one-directional (product-architecture.md §9): it imports
nothing from stages 1–4 and they never import it. Each link is a thin adapter in
a separate `Integrations/` folder that may import both sides, or a file exchange.

| Link | Data flow | How |
|---|---|---|
| BRSR Principle 6 / IFRS S2 metrics (Scope 1, 2, intensity, targets, transition plan) | GHG → stage 5 | Adapter adds GHG metrics to `ClimateDisclosureDraft` (corporate inventories first) |
| Wildfire burned area → AFOLU fire emissions and lost removals | Cell2Fire → GHG | Adapter turns a burned-area footprint into BASIC+ AFOLU entries (GPC forests & trees guidance) |
| Physical risk to mitigation assets (solar, STPs, depots) | GHG → stage 2 | Export plan assets in the exposure-intake file format; run the existing hazard → loss pipeline |
| Facilities and sites | Exposure / site lookup → GHG | Adapter seeds inventory facilities from stored sites |
| Dashboard tiles | GHG → dashboards | Read-only summary: total, goal status, plan progress |
