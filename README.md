<!-- Author: Ketney Otto
     Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
     Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154 -->

# Dairy CIP Digital Twin

> **Terminology (revision R1).** In the revised manuscript (*A safety-governed simulation framework for auditing the robustness of Pareto-optimal cleaning-in-place recipes in dairy processing*) this project is described as a **simulation framework**, i.e. a digital model in the sense of Kritzinger et al. (2018), and not as a digital twin, because it has no automated data exchange with a physical plant. The repository, file names and older sections of this README keep the term "digital twin" only for continuity of published links.

Proof-of-concept MATLAB/Simulink project for a dairy Cleaning-in-Place (CIP) digital twin, surrogate modeling, Pareto optimization, and governed Gemini-based reporting.

> All data, figures, metrics, and reports in this repository are **simulation-generated synthetic data**. The coefficients are proof-of-concept values and are **not calibrated to a real dairy plant**.

## Overview

The project combines four layers:

1. A mechanistic Simulink twin that generates synthetic CIP scenarios.
2. Machine-learning surrogate models that approximate the simulator outputs.
3. Multi-objective optimization that searches the water, energy, COD, CO2eq, and cleaning trade-off surface.
4. A governed Gemini layer that translates policy text, audits summary statistics, and explains Pareto solutions after the fact.

Gemini is never used inside the Simulink solver or the optimizer. It is a decision-support layer only, and it falls back to clearly labelled **Deterministic Offline Template Output** when no API key is configured.

## Repository Structure

- `src/` - MATLAB scripts and functions for model generation, simulation, validation, training, optimization, and Gemini integration.
- `model/` - the regenerable Simulink model `dairy_cip_digital_twin.slx`.
- `data/` - the simulation-derived synthetic dataset.
- `results/` - validation reports, surrogate metrics, Pareto solutions, policy JSON, and AI audit/explanation outputs (heavy binary `.mat` model states are ignored in Git but automatically rebuilt upon running the pipeline).
- `docs/` - methodology and limitations notes; Section 11 of `docs/methodology_note.md` documents the analyses added in the manuscript revision R1 (closed-form simulator, simulator-based Monte Carlo robustness audit, threshold and Sobol sensitivity, extended surrogate validation), whose scripts are in `src/` and outputs in `results/`.

The tracked `data/` and `results/` directories are intentional. They contain the reproducible study data and analytical results. Styling files, publication figures/tables, and heavy binary model states (`.mat`) are excluded from GitHub to maintain repository cleanliness and focus strictly on the code, data, and scientific logic.

## Requirements

- MATLAB R2026a.
- Required toolboxes:
  - Simulink
  - Statistics and Machine Learning Toolbox
  - Global Optimization Toolbox
- Optional toolboxes with graceful fallback:
  - Parallel Computing Toolbox - enables `parsim`; otherwise the pipeline uses serial `sim`
  - Stateflow - used for the phase scheduler; otherwise the model can be built with an equivalent MATLAB Function scheduler
  - Deep Learning Toolbox - not required by the default pipeline

For the Gemini layer, configure either `GEMINI_API_KEY` directly or use the project `.env` file. The loader also accepts `VITE_GEMINI_API_KEY` and `VITE_GEMINI_MODEL` and maps them to the canonical names.
Set `CIP_GEMINI_MODE=mock` to activate the **Deterministic Offline Reproduction Mode** for fully reproducible, network-free public-release checks (see the dedicated section below).

## Quick Start

From the project root in MATLAB:

```matlab
addpath('src')

% Build the Simulink model if needed.
run('src/build_model.m')

% Run the representative case-study simulations and export model/subsystem diagrams.
run('src/run_demo_simulations.m')

% Run the full study.
run('src/run_full_pipeline.m')

% Quick public-release smoke test.
setenv('CIP_GEMINI_MODE','mock'); setenv('CIP_N_SCENARIOS','50'); run('src/run_full_pipeline.m')

% Optional live Gemini run.
setenv('GEMINI_API_KEY','your-key-here'); run('src/run_full_pipeline.m')
```

If `model/dairy_cip_digital_twin.slx` is missing, build it first with `run('src/build_model.m')`.

## Automatic Toolkit Initialization Per MATLAB Session

This repository includes a **portable** `startup.m` at the project root (no
per-machine absolute paths, safe to commit). When MATLAB starts in this folder it:

- derives the project root from the script location and `cd`s to it, and adds `src/` to the path;
- if present, loads the **optional** Simulink Agentic Toolkit, resolved portably
  from the `CIP_SATK_PATH` environment variable, else `<user home>/.matlab/agentic-toolkits/simulink`;
  when found, it calls `satk_initialize` and `shareMATLABSession()`. If the toolkit
  is not installed, these hooks are **skipped silently** (no warnings);
- runs an optional, gitignored `startup.local.m` for machine-specific overrides.

So the agentic-toolkit integration is opt-in and machine-independent. To point at
a non-default toolkit location, set `CIP_SATK_PATH` (e.g. in `startup.local.m`):

```matlab
% Portable examples (no hard-coded absolute paths):
setenv('CIP_SATK_PATH', fullfile(getenv('USERPROFILE'), 'tools', 'agentic-toolkits', 'simulink'));  % Windows
setenv('CIP_SATK_PATH', fullfile(getenv('HOME'), 'tools', 'agentic-toolkits', 'simulink'));         % macOS / Linux
```

## Pipeline

`src/run_full_pipeline.m` executes the study in this order:

1. Scenario generation with Simulink.
2. Dataset validation.
3. Surrogate model training.
4. Gemini policy translation.
5. Pareto optimization.
6. Dataset summary generation.
7. Gemini plausibility audit.
8. Gemini Pareto explanation.
9. Figure generation.

The pipeline is designed to degrade gracefully. Missing optional toolboxes trigger documented fallbacks, and a missing Gemini key switches the AI layer to the Deterministic Offline Reproduction Mode instead of stopping the run.

## Scientific Reproducibility & Deterministic Offline Reproduction Engine

To guarantee that every dataset, figure, table, metric, and report in this
repository can be reproduced by editors and reviewers **without an active API
key, cloud cost, or network access**, the project ships a fully **Deterministic
Offline Reproduction Engine**, activated by setting `CIP_GEMINI_MODE=mock`:

```matlab
setenv('CIP_GEMINI_MODE','mock');   % Deterministic Offline Reproduction Mode
run('src/run_full_pipeline.m')
```

- **Cached Expert Templates.** In this mode the generative-AI decision-support
  layer is served entirely by a local, deterministic engine that returns
  pre-stored **Cached Expert Templates** emulating the structured behaviour of
  the large-language-model (LLM) layer. These templates carry the same
  governance labels and JSON schema as live responses, so every downstream step
  behaves identically — but no external model is ever contacted.
- **Zero-Dependency Open Science.** Because the templates are fixed and every
  numeric decision is computed by deterministic MATLAB code, the complete
  pipeline regenerates identical artifacts on any machine with the required
  toolboxes. Reviewers therefore obtain **100% offline reproducibility with no
  financial or technical barrier** — a property we term **Zero-Dependency Open
  Science**.
- **Provenance and transparency.** Every artifact produced this way is labelled
  **Deterministic Offline Template Output**, and `results/run_manifest.json`
  records the reproduction mode (`gemini_mode = MOCK`) together with per-artifact
  mode tags, so the offline provenance of the published study is fully auditable.
- **Optional live layer.** A live Gemini path remains available
  (`CIP_GEMINI_MODE=live` with a configured `GEMINI_API_KEY`) for authors who
  wish to regenerate the interpretive narrative online, but it is **never
  required** to verify the science: the solver, surrogate training, Pareto and
  robust optimization, the safety shield, and all figures/tables are computed
  without any AI call.

This engine underpins both the canonical pipeline and the AI-supervised
innovation/closed-loop pipelines, so the entire study — including the agentic
extension — is reproducible offline end to end.

## Agentic AI-Supervised Extension

Beyond the classic pipeline, the project adds an **AI-supervised, closed-loop digital twin** in which the generative-AI layer proposes hypotheses, designs simulation experiments, audits the model, formalizes policies, and recommends virtual supervisory setpoints — while every numeric decision stays in deterministic MATLAB, every recommendation passes a deterministic safety gate, human approval is mandatory, and direct real-time process control is explicitly excluded.

```matlab
addpath('src')
run('src/run_ai_closed_loop_study.m')   % agentic closed loop in the twin (default N=3)
run('src/run_policy_portfolio.m')        % same plant -> six context-dependent recipes
run('src/build_ai_decision_dossier.m')   % traceable human-in-the-loop dossier
```

New modules: `gemini_hypothesis_generator.m`, `validate_ai_hypotheses.m` (deterministic, no Gemini), `run_ai_designed_scenarios.m`, `build_model_equation_summary.m`, `gemini_model_auditor.m`, `ai_supervisory_control_recommender.m`, `cip_policy_profiles.m`, `build_run_manifest.m`, `build_ai_decision_dossier.m`. `run_full_pipeline.m` remains the canonical public full-study driver and writes `results/run_manifest.json`.

New artifacts: `results/ai_hypotheses.json`, `results/ai_hypothesis_validation.csv`, `results/ai_experiment_design.json`, `data/dairy_cip_ai_designed_dataset.csv`, `results/model_equation_summary.json`, `results/model_audit_report.json`, `results/ai_supervisory_recommendation.json`, `results/ai_closed_loop_trace.json`, `results/policy_portfolio_results.csv`, `figures/fig_policy_portfolio_tradeoffs.png`, `results/ai_decision_dossier.md`, `results/run_manifest.json`.

See `docs/README.md` (section 11) and `docs/methodology_note.md` (section 9b) for the full governance contract, the deterministic safety gate, and the LIVE/MOCK handling.

### Uncertainty-aware robust layer + safety shield + master pipeline

A second extension reframes the project as a **digital twin with AI supervisory
control, uncertainty-aware robust optimization, and a deterministic safety
shield**. One master script runs the whole innovation layer:

```matlab
addpath('src')
run('src/run_innovation_pipeline.m')                       % full innovation layer
setenv('CIP_INNOVATION_SKIP_CLOSED_LOOP','1'); run('src/run_innovation_pipeline.m')  % fast path (skip 8-min loop)
```

It chains: summaries + model audit → uncertainty surrogates → robust Pareto →
(optional) closed-loop study → supervisory recommendation behind the safety
shield → counterfactual study → decision dossier + manifest.

Additional modules: `train_uncertainty_surrogates.m` (quantile regression
forests → `models/uncertainty_surrogates.mat`, `results/uncertainty_surrogate_metrics.csv`),
`optimize_cip_robust_pareto.m` (`results/robust_pareto_solutions.csv`),
`safety_shield.m` (mandatory deterministic gate, used by the recommender),
`run_counterfactual_cip_study.m` (`results/counterfactual_cip_results.csv`, `.md`).

**The eight layers, distinguished:**

| Layer | What it does | AI role | Decides? |
|---|---|---|---|
| **Pareto optimization** | trade-off front over *mean* surrogate predictions (`optimize_cip_pareto`) | none | deterministic |
| **Robust Pareto** | front over *conservative quantile bounds*, penalizing uncertainty (`optimize_cip_robust_pareto`) | none | deterministic |
| **Uncertainty-aware** | quantile regression forests give lower/median/upper per target (`train_uncertainty_surrogates`) | none | deterministic |
| **AI policy translation** | natural-language policy → JSON constraints + 5 objective weights (`gemini_policy_translator`) | proposes | MATLAB validates/sanitizes |
| **AI supervisory recommendation** | picks a recipe from the front, explains it (`ai_supervisory_control_recommender`) | explains only | deterministic selection |
| **Safety shield** | independent hard-constraint gate on the chosen recipe, conservative bounds (`safety_shield`) | none — **AI cannot bypass** | deterministic, has veto |
| **Closed-loop feedback** | AI proposes experiments → simulate → retrain → re-optimize → re-recommend (`run_ai_closed_loop_study`) | proposes experiments/hypotheses | MATLAB verifies each step |
| **Counterfactual analysis** | "what-if" interventions and their predicted effects (`run_counterfactual_cip_study`) | none | deterministic |

In all cases the data are **simulation-generated synthetic data** and the
results require experimental calibration before any operational interpretation.

## Main Scripts

- `src/build_model.m` - constructs the Simulink digital twin reproducibly from the central parameter file.
- `src/run_demo_simulations.m` - runs the representative case-study simulations (archetypal scenarios), verifies `logsout`, exports model diagrams, and writes the reference case-study time-series.
- `src/run_cip_scenarios.m` - generates the simulation-derived synthetic dataset.
- `src/validate_outputs.m` - checks the dataset against plausibility ranges.
- `src/train_surrogate_models.m` - trains surrogate regressors.
- `src/gemini_policy_translator.m` - converts natural-language policy text into JSON constraints and weights.
- `src/optimize_cip_pareto.m` - runs the Pareto optimization step.
- `src/build_dataset_summary.m` - creates a compact dataset summary for auditing.
- `src/gemini_plausibility_auditor.m` - flags suspicious summary patterns for human review.
- `src/gemini_explain_pareto.m` - writes a post-hoc management explanation.
- `src/plot_results.m` - generates the publication figures.

## Expected Outputs

- `data/dairy_cip_synthetic_dataset.csv` - scenario inputs plus simulated outputs.
- `results/demo_simulation_results.csv` - the six representative case studies (archetypal scenario simulations) and their final simulated outputs.
- `results/demo_timeseries_*.csv` - reference case-study time-series for the representative recipes.
- `results/dataset_validation_report.txt` - validation summary.
- `results/surrogate_models.mat` - trained surrogate models (generated locally upon pipeline execution; not committed to Git).
- `models/uncertainty_surrogates.mat` - uncertainty surrogate models (generated locally during innovation pipeline execution; not committed to Git).
- `results/surrogate_metrics.csv` - held-out accuracy metrics.
- `results/pareto_solutions.csv` - Pareto-efficient solutions.
- `results/selected_policy_config.json` - selected policy configuration.
- `results/dataset_summary.json` - compact dataset summary.
- `results/plausibility_audit.json` - Gemini plausibility audit.
- `results/gemini_decision_report.txt` - Gemini explanation output.
- `results/run_manifest.json` - row counts, artifact fingerprints, Gemini mode, and pipeline status.

### Figures and Tables (Manual Post-Processing)

To maintain focus on the core scientific logic, the direct manuscript files (`manuscript/`), figure files (`figures/`), table files (`tables/`), and header utility tools (`tools/`) are excluded from GitHub. 

However, they can be reproduced locally at any time. Once the MATLAB pipeline runs successfully and exports the CSV artifacts to `data/` and `results/`, you can manually generate the publication-ready assets by running:

```powershell
# In your local project root:
python manuscript/make_figures.py
python manuscript/make_tables.py
```


## Simulink Model Architecture

`src/build_model.m` regenerates `model/dairy_cip_digital_twin.slx` as a visual,
inspectable top-level model with these subsystems: `Scenario Inputs`, `Phase
Scheduler`, `Soil Removal Kinetics`, `Water Consumption`, `Thermal Energy`,
`Pump Energy`, `Wastewater and COD`, `Hygiene and Risk`, `EHPI and Output
Metrics`, and `Logging and Scopes`.

Recipe parameters are exposed by clearly labelled Constant blocks in `Scenario
Inputs`: `T_C`, `Q_m3h`, `t_pre`, `t_alk`, `t_int`, `t_final`, `NaOH_pct`,
`soil0`, `heat_rec`, `water_rec`, and `T_in_C`. Automated runs override these
variables with `Simulink.SimulationInput.setVariable(...,'Workspace',mdl)`, not
with base-workspace `assignin`.

The wastewater model reports `COD_mgL` as an organic-load proxy based on
cumulative soil removed. NaOH residual is kept separate as
`NaOH_residual_mgL`; scripts can report `COD_chem_equiv_mgL` separately, but it
is not added to organic `COD_mgL`.

## Scientific Notes

The model boundary covers only the CIP cleaning cycle of a single dairy line. The outputs are environmental and hygiene proxies, not plant measurements. The cleaning score is a model-derived proxy, EHPI is a proposed synthetic index, and Gemini outputs are decision support only.

See `docs/methodology_note.md` for the modeling assumptions and `docs/limitations_note.md` for the explicit limitations and non-operational-use warning.

## First-Time Setup

1. Clone the repository.
2. Open it in MATLAB R2026a.
3. Add `src/` to the path.
4. Run `src/build_model.m` if the `.slx` file is missing.
5. Run `src/run_full_pipeline.m` for the canonical 5000-scenario study.

## Public Release Hygiene

The public branch intentionally excludes local agent instructions, scratch workspaces, bytecode caches, transient sentinels, secrets, redundant binary time-series caches, direct manuscript styling and formatting files (`manuscript/`, `figures/`, `tables/`, `tools/`), and heavy binary model states (`*.mat`). See `docs/public_release_manifest.md` for the retained-file classification, removal rationale, regeneration commands, header policy, and release scans.

## License And Use

This repository is a proof-of-concept research artifact. Do not use any recipe, coefficient, or conclusion operationally without industrial calibration, independent verification, and food-safety validation.


## Acknowledgments

This research was supported by the Google Cloud Research Credits program. All computations and data processing for this project were performed using infrastructure provided by Google Cloud.
