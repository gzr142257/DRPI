# Recorded source environment

The local source environment uses R 4.4.1 and the following installed package versions. This is an environment record, not a dependency lockfile or a claim that every other version has been tested.

| Package | Version | Repository |
| --- | --- | --- |
| glmnet | 4.1-10 | CRAN |
| randomForest | 4.7-1.2 | CRAN |
| dplyr | 1.1.4 | CRAN |
| MASS | 7.3-60.2 | CRAN |
| gamlss | 5.5-0 | CRAN |
| gamlss.dist | 6.1-1 | CRAN |
| partykit | 1.2-24 | CRAN |
| disttree | 0.2-0 | R-Forge |
| nortest | 1.0-4 | CRAN |
| quantregForest | 1.3-7.1 | CRAN |

The main R entry loads its shared dependencies even when only a subset of methods is selected. Install the complete main dependency set before running model fits. The numerical integration entry and stability `reference` mode use only base R; stability `experiment` mode uses `gamlss.dist`.

The Python helpers use the standard library. The optional manuscript figure-redrawing workflow expects an external figure script and `matplotlib`/`numpy`. The Windows batch runner uses PowerShell, and `complete_rerun.py` uses Windows process APIs.

Every recorded R run saves `sessionInfo.txt` so its actual package environment can be inspected.
