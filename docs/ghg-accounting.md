# GHG Accounting (GPC) workspace

A separate track from the physical-risk core: city GHG inventories under the
GPC, plus an activity × emission-factor calculator that can pull factors from
online databases. Code: `ClimateLiberatorApp/ClimateLiberator/ClimateLiberator/GHGAccounting/`.
Tests: `ClimateLiberatorTests/GHGAccountingTests.swift`.

## Workflow

Six pipeline steps, shown as numbered chips with live status:

1. **Boundary** — search a place (OpenStreetMap), preview its outline, then
   **Import boundary**; the chosen area turns green. Or draw points, or import
   GeoJSON/KML (EPSG:4326). Add city details and facilities (landfills, STPs,
   power plants).
2. **Activity data** — per GPC sector/sub-sector, add entries as activity ×
   factor, direct tCO2e, or a notation key (NO, IE, NE, C). Each entry keeps a
   snapshot of the factor it used.
3. **Review** — completeness for BASIC/BASIC+, failing entries, IE/NE keys
   without an explanation, and the largest lines on low/medium-quality data.
4. **Results** — totals, a chart picker (sector × scope, share by sector,
   largest sources, by gas, data quality, build-up to the total), the GPC
   sector × scope table, and export to
   `~/Library/Application Support/ClimateLiberator/Exports/GHG/`.
5. **Scenarios** — decarbonisation pathways against the base inventory: see
   [Scenarios](#scenarios-decarbonisation-pathways).
6. **Action Plan** — owner, timeline, cost per tonne, funding and co-benefits
   for each measure of a scenario: see [Action plan](#action-plan).

**Saving.** Nothing is written without asking. New inventories, the loaded
example and every edit stay in memory, marked *Not Saved*, until you choose
**Save** (⌘S). Quitting with unsaved inventories asks Save / Don't Save /
Cancel. The ⋯ menu offers Revert to Saved and Discard/Move to Trash.

**Tags on entries.** Scope 1–3; data quality High/Medium/Low (DQ, GPC rating
of activity data and factors); notation keys NO (not occurring), IE (included
elsewhere), NE (not estimated), C (confidential). IE and NE need an
explanation. The (i) next to the tags explains them in the app.

**Tools** (right of the steps) open a side panel next to any step: the
emission-factor **Calculator** and **Factor databases**. The calculator's
result shows the conversion steps, the gas split and an (i) note on the
method; the same result card appears in the activity-entry editor.

## GPC rules implemented

| Item | Rule |
|---|---|
| BASIC | Stationary energy and transport scopes 1–2; waste generated in the city (scope 1 and 3) |
| BASIC+ | BASIC + IPPU, AFOLU, T&D losses (I.x.3), transboundary transport (II.x.3) |
| Territorial only | I.4.4 grid generation, III.x.3 imported waste |
| Separate | Other scope 3 (VI.1), biogenic CO2 |
| Waste scope | Generated in city + treated inside → III.x.1; treated outside → III.x.2 |

Reference codes follow the GPC reporting template; check them against GPC
Table 4.3 before a formal submission.

## Boundary search (OpenStreetMap)

- Uses the Nominatim API (`format=jsonv2`, `polygon_geojson=1`, outline
  simplified to ~11 m). Search runs on Enter only, at most once per second,
  with an identifying User-Agent, per the Nominatim usage policy.
- Multi-part places (islands, exclaves) keep the largest part; holes are
  ignored. The app says when this happens.
- The source field records the OSM object, date and licence. Keep
  "© OpenStreetMap contributors (ODbL)" with any map or export you share.
- OSM outlines are community-mapped. Check them against the official ward or
  municipal map before formal reporting.

## Emission-factor databases

| Connector | Use for |
|---|---|
| Reference library | 120 offline factors: IPCC 2006 defaults + CEA grid factors (see below) |
| Climatiq | API key; live search; "Estimate with Climatiq" when search hides values |
| CSV over HTTPS | Published Google Sheet, GitHub raw file, open-data portal |
| JSON / REST | Supabase/PostgREST, Airtable, any in-house API (dot-path field mapping) |

- `{query}` in a URL enables live search; without it the whole file is cached.
- Default CSV columns: `name, unit, co2e` (+ optional `co2, ch4, n2o, region,
  year, source, category, gwp, id`). `unit` may be a full expression
  (`kg/kWh`, `tCO2e per MWh`); tonnes and grams are converted to kg.
- API keys live in the macOS Keychain, never in JSON. Only `https://` (or
  `http://localhost`) URLs are allowed.

## Reference library (offline)

| Group | Factors | Source |
|---|---|---|
| Stationary combustion | 18 fuels × 5 sectors (energy, manufacturing, commercial, residential, agriculture) | IPCC 2006 Vol. 2 Tables 1.2, 2.2–2.5 |
| Road | Petrol (uncontrolled, oxidation catalyst, low-mileage 1995+), diesel, auto LPG, CNG | Tables 3.2.1–3.2.2 |
| Off-road, rail, navigation, aviation | Diesel and petrol 2/4-stroke machinery, locomotives, marine diesel/RFO, jet kerosene, avgas | Tables 3.3.1, 3.4.1, 3.5.2–3.5.3, 3.6.4–3.6.5 |
| Solid waste | Composting, anaerobic digestion (per t wet) | Vol. 5 Table 4.1 |
| Wastewater | Septic, latrines, open sewer, river discharge (India BOD, per person-year) | Vol. 5 Tables 6.2–6.4 |
| Grid electricity | CEA v21 FY2024-25 weighted average (0.710); v20 FY2023-24 weighted average (0.727) and combined margin (0.757) | CEA CO2 Baseline Database |

Combustion CH4 uses the non-fossil GWP: IPCC 2006 already counts all fuel
carbon as CO2. CEA v22.0 (Aug 2026) covers FY2025-26 and is not bundled yet.

## Calculation rules

- Units convert within a dimension, and litres → kg → energy when a factor has
  density and net calorific value (the IPCC fuel factors do).
- GWP sets: IPCC AR4, AR5, AR6 (AR6 CH4 fossil 29.8, non-fossil 27.0, N2O 273).
  Factors with gas breakdowns are re-weighted; CO2e-only factors are not, with
  a warning.
- "MT" is rejected as ambiguous (metric tonne vs megatonne). Use `t` or `Mt`.

## Worked example: Iritty Municipality (Kerala)

**Load Iritty example** creates an illustrative GPC BASIC inventory (AR6). Most
lines are top-down: Kerala total × Iritty's population share
(52,318 / 36,111,000 = 0.145%). Replace each with local data before use.

| Line | Input | Source |
|---|---|---|
| Population | 52,318 (2025 projection) | AMRUT City Water Balance Plan, Iritty |
| Kerala population | 36,111,000 (July 2025) | Technical Group on Population Projections |
| Electricity | 27,675 MU × category shares | KSEBL FY2023-24 sales |
| LPG | 2,985 t/day domestic, 753 t/day non-domestic | Kerala figures for 26 Feb 2026 |
| Petrol | 1,851.3 TMT | PPAC, Kerala FY2024-25 |
| Diesel | 3 monthly sales figures, annualised | Kerala fuel-sales reporting, 2022–23 |
| Solid waste | 14.12 TPD, 70% composted | KSWMP C-EMP Iritty; Kerala 70–80% biodegradable |
| Wastewater | 34 g BOD/person/day, Bo 0.6, MCF 0.5 | IPCC 2006 Vol. 5 Ch. 6 |
| Composting | 4 g CH4, 0.24 g N2O per kg wet | IPCC 2006 Vol. 5 Ch. 4 Table 4.1 (reference library) |

Result ≈ 54,100 tCO2e BASIC (≈1.03 t per person). The boundary is Iritty
Municipality (LSGI M13083) from the OpenStreetMap Kerala local-body dataset
(opendatakerala/lsg-kerala-data, 2021; © OpenStreetMap contributors, ODbL):
192 points, ≈50.7 km² — larger than the 45.84 km² reported officially, so check
it against the municipal ward map. Inventories saved with the old 8-point
placeholder are upgraded when the app loads them.

Weakest inputs: diesel (annualised from three months) and wastewater
(assumes no septage removal).

## Scenarios (decarbonisation pathways)

A scenario = target year + business-as-usual (BAU) growth per sector + a set of
measures, each with adoption, start year, full year and editable parameters.
Saved with the inventory.

- **Create Starter Pathway** adds every catalog measure that fits the
  inventory's sources, needs no local input and cuts emissions by the target
  year (judged with the grid pathway).
- **Measure Library** (27 measures, 6 categories) shows each measure's
  stand-alone potential for this inventory: typical cut at default adoption,
  low–high range, % of base, and cut of its sources at 100% adoption.
- Charts: BAU vs scenario pathway (optional goal line) and the cut per measure
  in the target year. **Best Fits for Your Largest Sources** ranks measures for
  the top three sources.

**Method.** BAU grows activity, factors frozen. Measures apply in stage order —
demand → fuel switch → methane → clean supply → grid → removals — and compound
on what is left, so nothing is cut twice. A measure's bar is the drop in total
when it is applied. Fuel switches add grid electricity at that year's grid
factor (after the grid pathway), so their bars are their real net effect.
Removals are reported separately. Costs are not modelled.

**Defaults.** Every parameter cites a source or is tagged *Assumption*; each
measure links its main source. Measures tagged *Needs Input* (fans, solar water
heaters, LED street lights, industrial savings, trees, green cover) do nothing
until you enter a local count, area or rate.

**Removals.** Tree planting (IPCC 2019 Refinement: 0.005–0.01 t C per city tree
per year) and green cover (2.8 t C per ha of crown per year) are removals inside
the boundary — GPC AFOLU, which belongs to BASIC+. They are shown apart from
emissions (scenario line is net) and are not offsets: credits bought from projects
outside the city are kept out of the inventory total.

**Iritty check (BASIC, AR6, no growth):** base ≈54,100 t; starter pathway to
2035 ≈35,300 t (−35%). Largest cuts: grid pathway (CEA NEP), rooftop solar,
septic → aerobic STP, e-two-wheelers. LPG → induction adds emissions even on
the 2032 grid (0.81 kWh × 0.43 kg > 0.23 kg CO2 per kWh of LPG), so pair it
with rooftop solar or green power.

**Goals (GPC Chapter 11).** Below base year (%), below business as usual (%),
or a fixed level in the target year (0 = net zero), checked against emissions
net of in-boundary removals. Intensity goals need a population or GDP
projection and are not offered yet.

## Action plan

For the selected scenario (shared with step 5):

- **Per measure:** lead owner and partners, status (Proposed → Completed),
  city influence (direct control, enable, advocate), capital cost, lifetime,
  yearly running cost and savings, main funding source and scheme, co-benefits,
  notes. Rollout years and adoption come from the scenario.
- **Cost per tonne** = (capital × capital recovery factor + running − savings)
  ÷ target-year cut. The discount rate (default 8%) is an assumption. Costs are
  user inputs; the app does not estimate them.
- **Charts:** marginal abatement cost curve (cheapest first, width = tonnes),
  delivery timeline coloured by status, co-benefit coverage.
- **Off the curve:** a measure needs a cut in the target year to have a cost
  per tonne. A costed measure without one (0% adoption, rollout starting after
  the target year, no matching sources, or adding emissions) is listed under
  the curve with the reason; at 0% adoption the measure offers "Use typical".
  Scenarios tags 0% measures "No Effect".
- **Plan checks:** figure-changing gaps first (no cut, missing lifetime), then
  missing owners or funding, then status that contradicts the rollout years
  (Under Way before the start year, Completed before full adoption). Click a
  check to open the measure.
- **Residual emissions:** gross, in-boundary removals, net, and planned credits
  from outside the boundary with an optional ceiling. Per GPC Section 4.4,
  credits are reported separately and never deducted from the inventory.
- **Suggestions:** co-benefits, influence and possible Indian schemes (PM Surya
  Ghar, PM E-DRIVE, PM-eBus Sewa, SBM-U 2.0, AMRUT 2.0, Nagar Van Yojana,
  GOBARdhan) pre-fill the plan; scheme status was checked in November 2026 and
  changes often.
- **Export CSV** writes `action_plan.csv` and `pathway.csv` beside the GPC
  exports. Plans are saved with the inventory (only when you choose Save).
- **Iritty example:** *Load Iritty Example* now includes a 2035 pathway and
  plan (also available from Scenarios ⋯ → *Add Iritty Example Pathway* for an
  existing Iritty inventory). Illustrative: activity grows with population
  (1.9%/yr, 2011–2025), goal −30% vs 2025, owners are the usual Kerala agencies.
  Only rooftop solar is costed (₹55,000/kWp, 1,300 kWh/kWp/yr, savings at
  KSERC's ₹7.17/kWh average cost of supply); other costs are left for quotes.

Corporate (GHG Protocol) scenarios reuse the same engine and catalog through a
second baseline adapter: see [GHG architecture](ghg-architecture.md).

## Limits — verify before formal use

- Library values are Tier 1 defaults, not local data. Fuel densities are
  typical values. Use the CEA version that matches the consumption year.
- Boundary area is WGS84 ellipsoidal (authalic-latitude method); it matches
  geodesic area to about 0.002% at city scale.
- T&D losses, VKT models and waste first-order decay are not automated —
  enter their results as activity or direct CO2e.
- Scenario defaults are national or literature averages; the grid pathway is
  CEA's NEP projection, not a commitment. Replace with local data.
- Climatiq estimate unit strings are mapped from the app's symbols and have not
  been tested against a live key.
