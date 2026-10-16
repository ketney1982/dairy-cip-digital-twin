<!-- Author: Ketney Otto
     Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
     Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154 -->

# Public Release Manifest

Run date: 2026-06-02

Repository: ketney1982/dairy-cip-digital-twin

Release intent: public scientific repository for reproducing and documenting a
simulation-generated synthetic dairy CIP digital-twin manuscript.
Validation environment: MATLAB 26.1.0.3251617 (R2026a) Update 2 on Windows 11.
Required release toolboxes observed: Simulink, Statistics and Machine Learning
Toolbox, Global Optimization Toolbox, Parallel Computing Toolbox, Stateflow.

All retained data, figures, tables, metrics, JSON files, and AI reports are
simulation-generated synthetic artifacts. They are not real industrial
measurements and are not calibrated for operational CIP use.

## Gemini State

The public workflow supports `CIP_GEMINI_MODE=auto|mock|live`. For public
regression and release checks, use `CIP_GEMINI_MODE=mock` unless a live Gemini
run is deliberately documented. The Gemini API key is never committed, never
written to manifests, and is not required by Simulink, surrogate training,
Pareto optimization, safety shielding, or figure/table regeneration.

Current release validation refreshed the AI-support artifacts in the forced
**Deterministic Offline Reproduction Mode** (`CIP_GEMINI_MODE=mock`) and rebuilt
`results/run_manifest.json`; the manifest reported `gemini_mode = MOCK` with zero
consistency warnings.

## Files Kept

### Source Necessary

- `.env.example` - placeholder-only environment template.
- `.gitignore` - public ignore policy for secrets, caches, local agent files,
  Simulink build outputs, and redundant generated binaries.
- `README.md` - public project overview and reproducibility instructions.
- `CONTRIBUTING.md` - public contribution and validation rules.
- `CITATION.cff` - citation metadata for public release.
- `startup.m` - portable startup helper; machine-local overrides remain in
  ignored `startup.local.m`.
- All `src/*.m` files - MATLAB source for model build, scenario generation,
  validation, surrogate training, Pareto/robust optimization, governed Gemini
  calls, safety shielding, counterfactual studies, and manifests.

### Model Necessary

- `model/dairy_cip_digital_twin.slx` - Simulink model, regenerable from
  `src/build_model.m` and central parameters.

### Synthetic Data Necessary

- `data/dairy_cip_synthetic_dataset.csv` - canonical 5000-row simulation-derived synthetic dataset.
- `data/dairy_cip_ai_designed_dataset.csv` - synthetic AI-designed scenarios.
- `data/dairy_cip_ai_designed_accumulated.csv` - accumulated AI-designed
  synthetic scenarios for the closed-loop extension.
- `data/dairy_cip_combined_dataset.csv` - base plus AI-designed synthetic rows.

### Results Needed For Manuscript Reproduction

- `results/dataset_validation_report.txt`, `results/dataset_summary*.json` -
  validation and summary evidence.
- `results/surrogate_metrics.csv`, `results/surrogate_pred_vs_obs.csv`,
  `results/uncertainty_surrogate_metrics.csv`,
  `results/uncertainty_pred_vs_obs.csv` - surrogate performance evidence.
- `results/pareto_solutions.csv`, `results/robust_pareto_solutions.csv`,
  `results/selected_policy_config.json`, `results/policy_portfolio*.csv`,
  `results/counterfactual_cip_*.csv`, `results/counterfactual_cip_report.md`,
  `results/counterfactual_closed_form.csv` -
  optimization and policy/counterfactual outputs.
- `results/ai_*.json`, `results/ai_*.txt`, `results/ai_decision_dossier.md`,
  `results/gemini_decision_report.txt`, `results/model_audit_report.json`,
  `results/model_equation_summary.json`, `results/plausibility_audit.json` -
  governed AI-support artifacts retained only with synthetic-data disclaimers,
  mode labels, and research-only language.
- `results/demo_simulation_results.csv`, `results/demo_timeseries_*.csv`,
  `results/fig*.csv` - CSV dependencies for manuscript figures.
- `figures_tables_manifest.md` - the figure/table artifact manifest.
- `docs/README.md`, `docs/methodology_note.md`, `docs/limitations_note.md` -
  public documentation of methods, limitations, and governance.

## Files Removed From Public Release / Ignored And Not Published

The following files and directories are completely ignored by Git and excluded from the public GitHub repository:

- `AGENTS.md` and `CLAUDE.md` - private agent instructions replaced by neutral public documents.
- `_scratch/` - local scratch scripts, logs, and temporary working files.
- `manuscript/` - the authors' plotting and manuscript formatting scripts (graphical layout only; not distributed).
- `figures/` and `tables/` - final rendered PNG figures and Word DOCX tables. **Intentionally excluded by design**, to keep the public repository focused strictly on the *pure computational core* (deterministic code plus simulation-derived data) and to separate it cleanly from the *aesthetic presentation layer* of the manuscript. No scientific content is lost: the plotting scripts are not distributed, but every figure and table is a direct rendering of the tracked `data/` and `results/` files, which are listed per figure and table in `docs/methodology_note.md` (Section 11). This separation keeps the versioned history free of large binary renders and ensures that every plotted value can be checked against the committed numeric evidence.
- `tools/` - author header checking tools and private release scans.
- `*.mat` (e.g., `results/surrogate_models.mat`, `models/uncertainty_surrogates.mat`) - heavy binary model state files (excluded from GitHub for repository hygiene; automatically regenerated locally when running the MATLAB pipelines).
- `.env`, `.env.*` except `.env.example` - environment secrets and local configurations.
- `.claude/` - agent state files.
- `startup.local.m` - machine-specific startup overrides.
- `slprj/` and `*.slxc`, `*.asv`, `*.autosave`, `*.slx.bak` - Simulink build caches and backups.
- `__pycache__/`, `*.pyc` - Python bytecode cache.
- `results/_*.txt` - pipeline sentinels/logs.

## Regeneration Commands

Minimum public smoke check:

```matlab
addpath('src')
setenv('CIP_GEMINI_MODE','mock')
setenv('CIP_N_SCENARIOS','50')
run('src/run_full_pipeline.m')
run('src/validate_outputs.m')
```

Canonical full manuscript regeneration:

```matlab
addpath('src')
setenv('CIP_GEMINI_MODE','mock')  % or document live mode explicitly
setenv('CIP_N_SCENARIOS','5000')
run('src/run_full_pipeline.m')
run('src/run_innovation_pipeline.m')
run('src/build_ai_decision_dossier.m')
```

Author-header check (local/private asset only; folder excluded from GitHub):

```powershell
python tools/check_author_headers.py
```

Secret/path scan:

```powershell
rg -n --hidden -g '!.git/**' -e 'AIza[0-9A-Za-z_-]{20,}' -e 'sk-[A-Za-z0-9_-]{20,}' -e 'GEMINI_API_KEY\s*=' -e 'VITE_GEMINI_API_KEY\s*=' -e 'C:\\Users\\|G:\\|Contul meu Drive'
```

Tracked-disallowed-file scan:

```powershell
git ls-files | rg '(^_scratch/|__pycache__|\.pyc$|\.env$|slprj/|\.slxc$|_regen_status\.txt$|^manuscript/|^figures/|^tables/|^tools/|\.mat$)'
```

## Header Exceptions

Headers are applied to comment-safe source, configuration, Markdown, and CFF
files. They are intentionally not inserted into `.csv`, `.json`, `.mat`, `.slx`,
`.png`, or `.docx` artifacts because that would break parsers or binary
integrity. Plain `.txt` generated reports retain their generated format; author
and affiliation are documented here, in `README.md`, and in `CITATION.cff`.

## Validation Evidence To Record After Final Run

- MATLAB/toolbox version from `ver`: MATLAB 26.1.0.3251617 (R2026a) Update 2;
  Simulink, Statistics and Machine Learning Toolbox, Global Optimization
  Toolbox, Parallel Computing Toolbox, and Stateflow all available.
- Canonical validation command: `matlab -batch "addpath('src'); setenv('CIP_GEMINI_MODE','mock'); setenv('CIP_N_SCENARIOS','5000'); run('src/run_full_pipeline.m'); run('src/validate_outputs.m')"`
- Canonical result: 14/14 pipeline steps `OK`; `PIPELINE COMPLETE` in 550.4 s.
- Dataset validation result: 5000 rows; solver success 5000/5000; process
  feasible 5000; quality pass 3086; no warnings.
- AI-support refresh: hypotheses, experiment design, six AI-designed scenarios,
  hypothesis validation, model audit, supervisory recommendation, run manifest,
  and AI decision dossier regenerated under `CIP_GEMINI_MODE=mock`; hypothesis
  validation used 5006 rows (5000 synthetic + 6 AI-designed).
- `results/run_manifest.json`: `pipeline_status = OK`, `gemini_mode = MOCK`,
  consistency warnings 0.
- `git diff --check`: passed.
- Header check: `python tools/check_author_headers.py` passed.
- Secret/path scan: only documented placeholders in `.env.example` and the
  documented scan command in this manifest.
- Tracked-disallowed-file scan: run after staging/removal from the index.
