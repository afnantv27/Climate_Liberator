## TL;DR

```
sudo apt-get install doxygen
cd /Users/afnan/Desktop/Climate-Liberator/docs
doxygen Doxyfile
```

The generated files will be saved to the docs directory.

## Product direction

The canonical source of truth for what Climate Liberator is and what gets built
next:

- `product-architecture.md` — the five-stage peril-agnostic core, the anti-drift
  rule, the keep/park/build map, and the sequenced next steps. **Read this first.**

## Engineering docs

- `qa-benchmark-report.md`

## Parked (post-validation) docs

Enterprise-scale plans that are valid *later* but premature for a pre-user
product. See `product-architecture.md` §6 for why they are parked.

- `future/enterprise-readiness-plan.md`
- `future/sli-slo-catalog.md`
- `future/production-optimization-roadmap.md`

## Prerequisites

Ensure you have Doxygen installed on your system. You can find installation instructions in
the [official Doxygen documentation](https://www.doxygen.nl/manual/install.html).

## Writing documentation

Function docstrings should include:

- A brief description of the function.
- A more detailed explanation if necessary.
- A list of parameters with their types and descriptions.
- A description of the return value.
- A scientific reference if applicable.

To add a scientific reference in the code:

1. Add the citation in `docs/bibliography.bib` using `BibTeX` format.
2. Use the `@cite` tag in the function's docstring to reference the citation ID.

## Generating the documentation

Go to the `docs` directory and run the command `doxygen Doxyfile`. The generated HTML files will be stored in that
same
directory. You can open the main file `docs/html/index.html` using your favorite browser.
