# Climate Liberator — Product Architecture

> This is the single source of truth for what Climate Liberator is and what gets
> built next. If another document (or an AI coding session) suggests work that
> contradicts this file, this file wins. Update this file deliberately; do not
> drift around it.

Last reviewed: 2026-06-23

## 1. What this product is (one paragraph)

Climate Liberator is a **peril-agnostic climate-risk core** that turns a physical
hazard into a financial impact and then into a report. It is **India-first** and
serves **two buyers from the same core**: insurers/reinsurers (who want
catastrophe metrics) and corporate sustainability teams (who want regulatory
disclosure). Wildfire is **not** the product — it is the first hazard plug-in and
the test harness that proves the core works end to end.

## 2. The anti-drift rule (read this before building anything)

> **A framework is proven only by a vertical slice through it — never by the
> abstractions themselves.**
>
> At every step, the system must run **one real peril (wildfire) all the way to
> one real disclosure output (IFRS S2 / BRSR)**. If a layer cannot be exercised
> by that slice, it is not allowed to be built yet.

This rule exists because the project previously drifted: inherited wildfire code
made wildfire the strategy, and a premature enterprise roadmap made microservices
and SLAs feel like progress before there was a single user. Both are parked (see
§6). Wildfire is now a harness, not a goal. Enterprise-scale work waits for a
validated buyer.

## 3. The five-stage core

Every piece of code belongs to exactly one stage. Stages 1–4 are
**peril-agnostic and buyer-agnostic**; only stage 5 forks by buyer. Peril-specific
logic lives **only** inside plug-ins behind a stable interface and must never leak
upward.

```
1. HAZARD        "how intense, and where"          [peril-specific plug-in]
   Cell2Fire (wildfire) today. Flood / cyclone later, as new plug-ins.
   Output: a hazard intensity surface / footprint.
        │
        ▼
2. EXPOSURE      "what is at risk, where, worth how much"   [peril-agnostic]
   OED intake + India SQLite store. Assets, locations, values (TIV).
        │
        ▼
3. VULNERABILITY "given intensity X on asset type Y, what % damage"  [interface
   peril-agnostic, curves peril-specific]
   Damage / vulnerability curves. THIS IS THE CURRENT GAP.
        │
        ▼
4. FINANCIAL     "damage → money"                  [peril-agnostic, buyer-agnostic]
   FinancialLossEngine (GUL / IL / RI layering). Serves both buyers.
        │
        ▼
5. REPORTING     two thin surfaces over the SAME numbers
   (a) Insurer view:    AAL, PML, exceedance (EP) curve, accumulation
   (b) Disclosure view: IFRS S2 + SEBI BRSR narrative + metrics
```

Why "both buyers" is viable: stages 1–4 are identical for both. Only stage 5
forks. That is the entire product bet. It holds **only if** stages 1–4 stay
genuinely peril- and buyer-agnostic.

## 4. Buyers and frameworks

| | Insurer / reinsurer | Corporate sustainability |
|---|---|---|
| Wants | AAL, PML, EP curve, portfolio accumulation | Auditable disclosure: governance, scenario, metrics |
| Core code | `FinancialLossEngine`, OED intake, India risk DB | reporting surface over the same financial output |
| Depth | Very high (actuarial, validated) | Moderate (structured, auditable) |
| Sales motion | Long, technical, regulated | Compliance-deadline driven |

**Framework re-anchor (important):** TCFD was disbanded and folded into
**IFRS S2 (ISSB)**. Do not build toward TCFD as a standalone target. The
disclosure surface targets:

- **IFRS S2** — physical-risk and climate-scenario-analysis disclosures.
- **SEBI BRSR** — the actual Indian mandate (top 1,000 listed companies by market
  cap; **BRSR Core** carries assurance requirements). This is the India-first
  disclosure anchor.

Existing TCFD code is not wasted: its content maps into IFRS S2. Relabel, do not
discard.

## 5. Keep / generalize / decompose / park

| Existing area | Verdict | Reason |
|---|---|---|
| `Cell2Fire` engine + embedded lib | **Keep, isolate** | First `HazardModel` plug-in. Must not leak wildfire concepts upward. |
| `FinancialLossEngine` | **Keep, promote** | Stage 4 core. Already buyer-agnostic. |
| `ExposureIntake` / OED / India SQLite store | **Keep, generalize** | Stage 2. Strip any wildfire-specific assumptions. |
| Vulnerability curves | **BUILD — this is the gap** | Hazard and money exist; the intensity→damage middle does not. |
| `TCFDDashboard*` + TCFD stores | **Relabel + decompose** | Re-anchor to IFRS S2, add BRSR mapping. Break the 2,694-line monolith into per-pillar views. |
| `ContentView.swift` (4,856 lines) | **Decompose — urgent** | Primary source of "losing track". Split per workspace, no behavior change. |
| `EnterprisePlatform*` contracts, SLO catalog, readiness plan | **Park (`docs/future/`)** | Premature for a pre-user product. Do not build against it yet. |

## 6. What is parked (and why it is not deleted)

Moved to `docs/future/` — valid *later*, wrong *now*:

- `enterprise-readiness-plan.md` — microservices, 99.9% SLAs, HA/DR for a product
  with no users. Revisit after the first validated buyer.
- `sli-slo-catalog.md` — SLO targets with no live traffic to measure.
- `production-optimization-roadmap.md` — optimization ahead of validation.

Parking is reversible. When there is a paying user and real load, promote the
relevant pieces back.

## 7. Sequenced next steps

Each step must keep the **wildfire → BRSR** slice running.

1. **Define the 5 core protocols** — `HazardModel`, `ExposureSet`,
   `VulnerabilityCurve`, `FinancialModel`, `ReportSurface`. Small, one file. Make
   Cell2Fire implement `HazardModel`.
2. **Decompose `ContentView.swift`** into per-workspace files. Pure structure, no
   behavior change. Buys back maintainability.
3. **Build the vulnerability layer** (stage 3) — even crude curves — so wildfire
   intensity actually drives `FinancialLossEngine` instead of being hand-wired.
4. **Fork the reporting surface** (stage 5) — rename TCFD → IFRS S2, add a BRSR
   field mapping. One run then produces both an insurer summary and a disclosure
   draft.
5. **Add a second peril** (flood or cyclone) as a second `HazardModel`. This is
   the real test of the framework. If steps 1–4 were honest, this is mostly data
   plus one model, not a rewrite.

India specifics fall out naturally: exposure is already India-SQLite-backed; the
disclosure surface targets BRSR; the high-value second peril for India is **flood**
or **cyclone** (not wildfire).

## 8. Definition of done for "the framework works"

The framework is validated when a single run, with no wildfire-specific code above
stage 1, produces **both**:

- an insurer-facing loss summary (AAL / PML / EP curve), and
- an IFRS S2 / BRSR-shaped disclosure draft,

and a **second peril** can be added by implementing only a new `HazardModel` plus
its vulnerability curves — touching nothing in stages 2, 4, or 5.
