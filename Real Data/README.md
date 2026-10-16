# Real-data input files

Supply the following comma-separated files with a header row in this directory, or pass `--data-root=PATH` to the R main entry (`-DataRoot` to the PowerShell launcher).

| Dataset option | Filename | Response column used by the loader |
| --- | --- | --- |
| `Diabetes` | `diabetes.csv` | `target`, or the last column when `target` is absent |
| `Concrete` | `concrete.csv` | Last column |
| `WineRed` | `red_wine.csv` | `quality`, or the last column when `quality` is absent |
| `Boston` (optional) | `Boston.csv` | `medv` |

The local Diabetes format has predictors `age, sex, bmi, bp, s1, s2, s3, s4, s5, s6` and response `target`. Predictors and responses must be suitable for numeric regression. The WineRed loader uses `read.csv`, so a semicolon-separated source must first be converted to comma-separated CSV. Do not add an exported dataframe row-index column.

The default full batch uses Diabetes, Concrete, and WineRed; Boston is only an optional individual entry. The built-in simulations need no CSV files.

Raw datasets are not distributed with this repository. Obtain them from their original providers under their applicable terms. To reproduce an existing run exactly, use the same data version, preprocessing, row order, seeds, and package environment. The sample-337 analysis also depends on the original Diabetes row order and expected split membership.

The stability script contains its calibration-size table in source. A local copy of `Universal distribution of the empirical coverage in split conformal prediction.pdf` is optional metadata; it is not needed for calculation and is not redistributed here.
