# Original research-maintenance tools

The core experiments can be run independently using the commands in the root README. The following additional source files are retained for transparency, but their historical inputs are not bundled.

| Tool | Required external context |
| --- | --- |
| `src/generate_latex.py` | Saved main, sensitivity, stability, and optional case/theory results; manuscript table templates; optional figure-redrawing script |
| `src/run_parallel_experiments.py` | An existing batch directory with `parallel_resume_plan.json`, previous result layout, and an explicit `--rscript` path |
| `src/verify_rerun.py` | A recorded four-stage batch, historical comparison CSVs, and manuscript table context |
| `src/complete_rerun.py` | A Windows batch process, its PID, recorded batch inputs, and an explicit `--rscript` path |

Use each tool's `--help` for its options. These are workflow-specific utilities, not general entry points for a fresh checkout.

`generate_latex.py` defaults to manuscript templates beneath `Latex/DRPI_revised_source_20261002/` and legacy results beneath `src/experiment_results/`. Supply `--paper-root`, `--result-root`, `--sensitivity-root`, `--stability-csv`, and the other applicable options for your own inputs. Its `--check-only` mode still requires the source results and existing manuscript templates. `--redraw` additionally requires the manuscript's `figures/redraw_stability.py`.

The original `publication_sources.json` is deliberately not included because it pins a historical local run. If you create a new one beside `generate_latex.py`, its paths are interpreted relative to `src/`. Audit manifests contain result paths and hashes; old absolute paths must resolve to the same files in the current environment before verification can succeed. Do not treat an absent historical manifest as proof that results were independently reproduced.

The historical run archive and previous result tables are excluded from this source release. Full paper reproduction requires those inputs or freshly generated results using the complete experiment protocol.
