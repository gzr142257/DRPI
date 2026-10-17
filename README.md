# DRPI

**Distributional Residual Prediction Intervals** — research code for C-DRPI and G-DRPI, baseline comparisons, empirical coverage stability experiments, and Gaussian interval-length variance calculations.

DRPI（分布型残差预测区间）实验源码。主要计算使用 R；Python 和 PowerShell 提供入口检查、批处理及论文结果维护工具。下方示例均从仓库根目录运行。

## Methods

| Method | Command-line method | Result filename |
| --- | --- | --- |
| C-DRPI (conditional residual distribution) | `C-DRPI` | `C-DRPI.csv` |
| G-DRPI (global residual distribution) | `G-DRPI` | `G-DRPI.csv` |
| Split conformal prediction | `splitcp` | `SplitCP.csv` |
| Local conformal, Gaussian kernel | `lcp-gaussian` | `LCP_Gaussian.csv` |
| Local conformal, nearest neighbors | `lcp-knn` | `LCP_kNN.csv` |
| LWCI | `lwci` | `LWCI.csv` |
| WCP | `wcp` | `WCP.csv` |
| ACPI | `acpi` | `ACPI.csv` |

Use `--method=both` for the two DRPI variants, `--method=all` for all eight methods, or a comma-separated subset. Evaluate coverage, interval length, and variation together. The implemented DRPI procedures do not establish finite-sample distribution-free coverage for their data-reuse construction.

`C-DRPI` and `G-DRPI` are the canonical method names in command examples, logs, result labels, and filenames. Method selection is case-insensitive. Internal R identifiers use `c_drpi`/`C_DRPI` and `g_drpi`/`G_DRPI` because a hyphen is an operator in R; these identifiers refer to the same two methods.

G-DRPI's expansion factor is selected with `--g-drpi-lambda=0.5`. With `--lambda-sensitivity-output=true`, its output is named `G-DRPI_lambda_<value>.csv`. The stability table is `G-DRPI_tau_table.csv`, and case-analysis records are `C-DRPI_replicates.csv` and `G-DRPI_replicates.csv`. All supplied result-reading tools use these same filenames.

## Installation

Clone the repository and make `Rscript` available on your PATH:

```sh
git clone https://github.com/gzr142257/DRPI.git
cd DRPI
```

The source environment uses R 4.4.1. Install these packages from an R session before running the main experiment:

```r
install.packages(c(
  "glmnet", "randomForest", "dplyr", "MASS", "gamlss", "gamlss.dist",
  "partykit", "nortest", "quantregForest"
), repos = "https://cloud.r-project.org")
install.packages("disttree", repos = c(
  "https://R-Forge.R-project.org", "https://cloud.r-project.org"
))
```

`disttree` is distributed through [R-Forge](https://r-forge.r-project.org/R/?group_id=261). Package availability depends on your R version; source installations may require the build tools appropriate to your platform. See [the recorded dependency versions](docs/dependencies.md).

The theory calculation and the coverage-reference export need only base R. The stability experiment additionally needs `gamlss.dist`. Python 3 is optional for the helper scripts; the entry checker uses only the Python standard library. The PowerShell batch runner is intended for Windows.

## Quick start

Export the 48-cell split-conformal reference table without fitting models or providing datasets:

```sh
Rscript src/empirical_coverage_stability.R --mode=reference --export-root=outputs/reference --runs-root=runs
```

Compute one Gaussian variance comparison:

```sh
Rscript src/theoretical_proof_numerical_integration.R --mode=single --n=50 --alpha=0.1 --export-root=outputs/theory --runs-root=runs
```

Run the two DRPI methods for one split of the built-in normal simulation (requires the main R dependencies):

```sh
Rscript src/conformal_prediction_pipeline.R --stage=main --dataset=sim_NO --base-model=elastic_net --method=C-DRPI,G-DRPI --n-seeds=1 --export-root=outputs/demo --runs-root=runs
```

Check method selection without loading model dependencies or fitting models:

```sh
python src/check_entries.py
```

If `Rscript` is not on PATH, pass its executable path, for example on Windows:

```powershell
python .\src\check_entries.py --rscript "C:\Program Files\R\R-4.4.1\bin\Rscript.exe"
```

## Experiments

The R entries accept `--help`. Options use `--name=value` syntax.

| Entry | Purpose |
| --- | --- |
| `src/conformal_prediction_pipeline.R` | Main comparisons (`--stage=main`), sample-337 analysis (`case337`), and Diabetes frequency analysis (`frequency`) |
| `src/empirical_coverage_stability.R` | Stability experiments (`--mode=experiment`) and exact split-conformal reference probabilities (`reference`) |
| `src/theoretical_proof_numerical_integration.R` | The 27-cell Gaussian variance calculation (`--mode=table`) or one setting (`single`) |
| `src/run_records.R` | Shared execution records; sourcing this file alone runs no experiment |
| `src/run_experiments.ps1` | Windows batch launcher for all experiment stages |

Built-in simulations are `sim_NO`, `sim1`, `sim2`, and `sim3`. Real-data entries are `Diabetes`, `Concrete`, `WineRed`, and optional `Boston`. Place your CSVs in [`Real Data/`](Real%20Data/README.md) or provide `--data-root=PATH`; raw datasets are not bundled with this source release.

Windows batch examples:

```powershell
# One simulated setting, all methods, 100 splits
powershell -NoProfile -File .\src\run_experiments.ps1 -Stage main -Dataset sim_NO -Seeds 100

# Full 13-setting comparison matrix; requires the three real-data CSVs
powershell -NoProfile -File .\src\run_experiments.ps1 -Stage main -DataRoot "C:\path\to\data"

# Stability (1000 repetitions per cell by default), theory, and sensitivity
powershell -NoProfile -File .\src\run_experiments.ps1 -Stage stability
powershell -NoProfile -File .\src\run_experiments.ps1 -Stage theory
powershell -NoProfile -File .\src\run_experiments.ps1 -Stage sensitivity -DataRoot "C:\path\to\data"
```

The full experiments are substantially larger than the quick-start checks. The stability defaults use 10,000 training observations, 300,000 test observations, and 1,000 repetitions per cell; use explicit smaller sample sizes when exploring the implementation. Small exploratory runs do not reproduce the full research protocol.

Each R execution writes a fresh record directory containing configuration, session information, source snapshots, input checksums, status, and outputs. Use `--runs-root` and `--export-root` to control their locations. The default record directory is `src/runs/`; the PowerShell runner creates a new batch beneath it. Generated records and outputs are ignored by Git.

## Additional research tools

`generate_latex.py`, `run_parallel_experiments.py`, `verify_rerun.py`, and `complete_rerun.py` preserve the original research-maintenance code. They require manuscript templates, existing result files, and/or recorded batch plans that are not part of this source release. `complete_rerun.py` uses Windows process APIs. See [the requirements for these tools](docs/research-tools.md) before running them.

This release uses consistent C-DRPI and G-DRPI names across source code, command-line options, output files, and research tools. The entry checker locates `Rscript`, and the reference-paper PDF is optional. Historical runs, manuscript files, reference PDFs, raw datasets, and previous result archives are not included. External result collections must use the current naming convention before being read by these tools.

## License

Copyright (c) 2026 Zirui Guo. Released under the [MIT License](LICENSE). External packages and independently obtained datasets retain their respective licenses.
