# Disclosure platform (BRSR, BRSR Core, IFRS S2)

The **Disclosure** workspace prepares SEBI BRSR / BRSR Core reports and IFRS S2
climate disclosures for one or many client companies. It replaces the old
TCFD "Disclosure Review" window (removed in Nov 2026).

## Who it is for

- **Sustainability consultants** run several client engagements side by side
  (All Clients view), send data requests, review and sign off.
- **Companies** run one engagement per financial year and roll it forward.

## Workflow

1. **Company & Scope** – profile, financial year, boundary, frameworks
   (the applicability check suggests them), team, assurance provider.
2. **KPI Data** – every BRSR Core KPI plus key BRSR and IFRS S2 metrics, with
   prior year, source, method, owner and evidence. Totals, intensities
   (₹ revenue, PPP-adjusted revenue, output), LTIFR, payable days and shares
   are calculated. Emissions can be **imported from a GHG Accounting
   inventory**, or calculated there first (*Calculate in GHG Accounting*).
3. **Narratives** – IFRS S2 pillars and BRSR qualitative items, each with a
   checklist of what it must cover and linked metrics.
4. **Risks & Opportunities** – one register feeds BRSR Section A (material
   issues) and IFRS S2 Strategy; heat map; physical-risk assessments
   (optionally from wildfire simulation packages) feed IFRS S2 29(c).
5. **Policies & Governance** – BRSR Section B policy matrix (P1–P9).
6. **Evidence** – document register linked to KPIs (assurance trail).
7. **Review & Approval** – submit → review → approve / request changes;
   final sign-off locks the engagement; full audit trail.
8. **Reports** – BRSR draft, BRSR Core assurance table, IFRS S2 draft,
   assurance pack, audit trail, data-request template (Markdown, HTML, CSV).

Nothing is written to disk until the user saves (⌘S); quitting asks.

## Code layout (`ClimateLiberator/Disclosure/`)

| Folder | Contents | May import |
|---|---|---|
| `Core/` | Codable models, storage locations, formatting, CSV | Foundation |
| `Catalog/` | Frameworks as data: metrics, derivations, narratives, applicability rules | Core |
| `Engine/` | Pure logic: metric resolver, readiness, data-quality checks, workflow rules, roll-forward, data-request import/export | Core, Catalog |
| `Reports/` | Format-neutral `ReportDocument`, Markdown/HTML/CSV renderers, report builders | Core, Catalog, Engine |
| `Integration/` | Thin adapters: GHG Accounting inventories, wildfire evidence packages, physical-risk drafting | everything above + the adapted module |
| `Store/` | `DisclosureStore` (state, saving, audit log), example engagement, quit guard | all non-UI layers |
| `Views/` | One file per section; shared components in `Views/Components` | all |

Rules: models, catalog, engine and reports are `nonisolated` and UI-free, so
they are unit-tested directly (`DisclosurePlatformTests`). Only `Integration/`
knows about other modules; GHG Accounting does not import Disclosure.

## Extending

- **New KPI**: add a `MetricDefinition` in `MetricCatalog.swift` (id, unit,
  BRSR/Core/IFRS links, guidance, optional `Derivation`). Readiness, checks,
  reports and the data-request template pick it up automatically.
- **New narrative**: add a `NarrativeRequirement` in `NarrativeCatalog.swift`.
- **New framework**: add a `DisclosureFramework` case, link metrics/narratives
  to it, and add a report builder in `Reports/`.
- **New export format**: add a renderer for `ReportDocument`.
- **Rule changes** (SEBI glide path, ISSB amendments): `ApplicabilityRules.swift`
  carries the rules and the date they were checked.

## Known limits

- Covers all BRSR Core KPIs and selected BRSR essential/leadership indicators;
  other BRSR questions go in narratives. No XBRL filing output yet.
- Paragraph references are for navigation; check them against the official
  SEBI formats and IFRS S2 text before filing.
- GHG import maps a GHG Accounting inventory's territorial, Scope 2 and
  Scope 3 totals to the company's Scope 1, 2 and 3. Use it only when the
  inventory was built for the company's own boundary.
- The old wildfire package review (board-ready, finance sign-off, threshold
  bands) has no editor since the TCFD window was removed; Executive Overview
  still shows its counts. Folding it into Review & Approval is a follow-up.
- Rules checked November 2026 (BRSR Core assessment-or-assurance glide path to
  top 1,000 in FY 2026-27; value-chain assurance voluntary; IFRS S2 not
  mandated in India).
