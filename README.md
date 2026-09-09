# Climate Liberator

An India-first macOS climate-risk workbench for hazard simulation, exposure
screening, financial-impact prototypes, forecast evidence and disclosure review.
Wildfire is the first hazard implementation, not a claim of multi-hazard coverage.

This is an actively developed desktop product, not an enterprise-certified risk
model or a hosted service with an SLA. See [Product Architecture](docs/product-architecture.md).

## Install or Build

The app targets **macOS 26.2 or later**. Packages are architecture-specific;
Apple Silicon is the locally tested target. The SwiftUI app is not a Windows
or Linux application.

Extract a compatible `Climate-Liberator-arm64.zip` and move `ClimateLiberator.app`
to Applications. The package includes its engine, native libraries, fuel tables
and a small offline starter dataset. End users do not need Homebrew, Xcode,
Python, a source checkout or the developer's Build folder for the packaged
**prepared-ASCII S simulation**.

The current package is locally signed for internal testing, **not notarized**.
Public distribution still needs appropriate signing/notarization. This change
does not automatically publish a downloadable release.

To build from the repository root on a Mac with Xcode and its command-line tools:

```sh
brew install libomp libtiff boost
open ClimateLiberatorApp/ClimateLiberator/ClimateLiberator.xcodeproj
# Or build, verify relocation, and create a local release ZIP:
bash scripts/package_macos.sh
```

Xcode 26.3 was used for local validation. Build scripts discover dependency
locations rather than assuming a Homebrew installation path. The package is
written to `.build/releases/` and is not committed to Git. Set
`CLIMATE_BUILD_DIR` or `CLIMATE_RELEASE_DIR` to change build/output roots.

## First Run and India Data

First launch installs writable starter resources:
- 12 **synthetic** building records near Bengaluru, labelled demonstration data.
- A synthetic 12 x 12, 30-metre Scott & Burgan study in UTM 43N.
- An INR-denominated example CSV for the current OED screening importer.

These are engineering fixtures, **not actual buildings, surveyed fuels, insured
values, a national dataset or an India-calibrated wildfire assessment**.
No live forecasts or precomputed risk assessments are bundled.

Use **Settings > India Data > Import India Database** to install an approved
database matching [the app schema](ClimateLiberatorApp/resources/india_schema.sql).
Imports validate schema/integrity, include committed SQLite WAL data, and retain
the previous installed database as a backup. Portfolio Intelligence also accepts
the app's OED screening files. This is not certification of complete OED
financial-contract support. Use verified exposure values and source provenance.

## Where Data Lives

| Location under your home folder | Contents |
|---|---|
| `Library/Application Support/ClimateLiberator/StarterData-v1/` | Writable starter study and synthetic exposure data |
| `Library/Application Support/ClimateLiberator/Data/India/` | Imported India database and pre-import backups |
| `Library/Application Support/ClimateLiberator/Data/Forecast/processed/` | User-installed processed forecast JSON and `manifests/` |
| `Library/Application Support/ClimateLiberator/Runs/` | Default simulation outputs |
| `Library/Application Support/ClimateLiberator/Exports/` | Default India screening exports |
| `Documents/ClimateLiberator/` | Existing scenario, disclosure and evidence storage |

Settings includes **Open Data Folder**. Existing explicit study/output/engine
preferences are preserved; **Use Bundled** clears an obsolete engine override.
Close the app and other database writers before migrating data to another Mac.
Back up both library and Documents locations, plus any custom output folders.
Git preserves source and bundled fixtures, **not private imported data or runs**.

Map tiles, place search and live forecasts require internet. Processed forecasts
must be current and near the selected location; synthetic, expired and distant
feeds are not silently substituted. GDAL-dependent reprojection/KMZ and Earth
Engine preparation remain optional, separately configured workflows.

## Product and Engine Boundaries

The app retains Dashboard, Portfolio Intelligence, Climate Simulation, Forecast
Intelligence, Executive Overview and Disclosure Review. Existing TCFD-named code
supports reporting work toward IFRS S2/BRSR drafts; it is not a claim of
regulatory compliance or actuarial validation.

The supported simulation UI targets **S (Scott & Burgan)**. The default backend
is built from the Cell2Fire-derived source in this repository and packaged inside
the app. Embedded and native-rewrite adapters remain experimental until their
scientific/output acceptance checks pass. The external `Build/engine-rewrite`
workspace is a development lab, **not an installation requirement**.

Speculative control-plane readiness panels have been removed from the active
shell. Reversible enterprise proposals remain under `docs/future/`; these are
not deployed authentication, multi-user services or proven availability.
See [the portability audit](docs/india-portability-audit.md).

## Tests

```sh
xcodebuild -project ClimateLiberatorApp/ClimateLiberator/ClimateLiberator.xcodeproj \
  -scheme ClimateLiberator -destination 'platform=macOS' test
xcodebuild -project ClimateLiberatorApp/ClimateLiberator/ClimateLiberator.xcodeproj \
  -scheme ClimateLiberatorUITests -destination 'platform=macOS' test
```

UI tests require an unlocked graphical Mac and test-runner permissions.
Unit tests include fresh installation, WAL-safe import, cache refresh,
latest-assessment rollups, a synthetic 100,000-asset benchmark, and forecast
selection/cache checks. Packaging copies the app to a path with spaces, checks
native dependency closure and seed hashes, and runs the synthetic S fixture
with a minimal environment.

## Repository Layout

```text
ClimateLiberatorApp/    SwiftUI app, tests, starter resources, native build scripts
Cell2Fire/              Cell2Fire-derived wildfire source and bridging API
scripts/               Starter generation and macOS packaging verification
data/                  Additional prepared engine fixtures
test/                  Inherited engine tests
docs/                  Architecture, QA, science notes and deferred plans
```

## Attribution

The wildfire subsystem derives from Cell2Fire and Cell2Fire W. Original
authorship and licensing remain intact; product branding does not remove those
obligations. See [LICENSE](LICENSE) and source notices. Packaged native
dependencies include available license notices in `Contents/Resources/Licenses`.
