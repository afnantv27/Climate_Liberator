# Platform architecture

Climate Liberator is organised by the work a consultant or company does, not by
framework. Toolbar order follows that work:

| Workspace | Folder | Purpose |
|---|---|---|
| Home | `Home/` | What needs attention across all clients; entry to each module |
| Clients | `Clients/`, `Clusters/` | Client register, sites (with coordinates), cluster benchmarks |
| Measure | `GHGAccounting/` | GHG inventories and emission-factor calculator |
| Reduce | `Reduce/` | Targets, measures, carbon credits; links to city action plans |
| Report | `Disclosure/` | BRSR, BRSR Core, IFRS S2 (see `disclosure-platform.md`) |
| Climate Risk | `Climate*` / simulation files | Wildfire simulation today; more hazards planned |

Removed in Nov 2026: Dashboard launcher, Executive Overview and Portfolio
Intelligence (replaced by Home and Clients). Their services (OED intake, India
risk store) remain for later reuse.

## Layers

| Folder | Holds | May depend on |
|---|---|---|
| `Shared/` | Design system, `WorkspacePage`, formatting, CSV/JSON, document folders, unsaved-work protocol, domain types (`IndustrySector`, `ReportingPeriod`, `ClientYearFigures`) | Foundation, SwiftUI |
| Module `Core/` | Codable models with tolerant decoding | Shared |
| Module `Engine/` | Pure, `nonisolated`, unit-tested logic | Core, Shared |
| Module `Store/` | One `ObservableObject` per module | Engine, Core, Shared |
| Module `Views/` | SwiftUI, one file per screen or card | everything in its module |
| `Platform/Integration/` | Adapters between modules (e.g. KPI Data → `ClientYearFigures`, example cluster) | modules |
| `Platform/Navigation/` | `AppWorkspace`, workspace construction and cross-workspace navigation | all |

Rules:
- Modules talk through `Shared` types and `Platform/Integration`, never by
  reaching into another module's views or stores.
- `ClientYearFigures` is the common currency for performance data. KPI Data
  produces it today; corporate inventories will produce it later, with no change
  to Clusters, Reduce or Home.
- Every store keeps edits in memory, saves only when asked, and conforms to
  `UnsavedWorkProviding`; `UnsavedWorkGuard` asks once at quit for all of them.
- Saved files: one JSON file per document under `AppData/<Module>/`, written
  atomically; deletions go to the Trash.

## Adding a module

1. Create `<Module>/Core`, `Engine`, `Store`, `Views`.
2. Store: load with `JSONDocumentFolder`, register with `UnsavedWorkRegistry`.
3. Add a case to `AppWorkspace`, a view in `ContentView+Platform.swift`, and
   route it in `ClimateLiberatorWorkspaceShellView`.
4. Unit-test the Engine; add an attention rule to `HomeSummary` if relevant.

## Known limits

- Cluster benchmarks and target progress read KPI Data; each client needs an
  engagement (Clients → Start Data Collection) until corporate inventories exist.
- SBTi checks are reference checks only; required rates depend on base year and
  scope mix. Confirm with SBTi's current criteria before submission.
- Credits are never netted from emissions in reports.
