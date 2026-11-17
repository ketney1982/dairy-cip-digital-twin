<!-- Author: Ketney Otto
     Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
     Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154 -->

# Self-Explaining Digital Twin for Environmental Decision Support in Dairy CIP Systems

**Coupling Simulink simulation, surrogate modeling, Pareto optimization and generative AI.**

> ⚠️ **All data in this project are SIMULATION-GENERATED SYNTHETIC DATA.**
> They are produced by a simplified mechanistic model with proof-of-concept
> coefficients and are **not** real industrial measurements. Nothing here is
> validated against plant data or food-safety standards.

---

## 1. Project purpose

This repository implements a **simulation-first, AI-assisted environmental
decision-support framework** for dairy **Cleaning-in-Place (CIP)** systems. A
mechanistic Simulink digital twin generates controlled synthetic process data;
machine-learning surrogates accelerate environmental prediction; multi-objective
optimization identifies trade-off-efficient CIP strategies; and a generative-AI
(Gemini) layer translates natural-language policies into optimization
constraints, audits the plausibility of the simulation, and explains the final
trade-offs to managers.

## 2. Scientific rationale

CIP is one of the largest consumers of water, thermal energy and cleaning
chemicals in a dairy plant, and a major source of high-COD wastewater. Studying
trade-offs experimentally is expensive and slow. A **mechanistic simulator**
provides cheap, controllable, reproducible *synthetic* experiments; **surrogates**
make optimization tractable; **Pareto optimization** exposes the water / energy /
COD / CO₂ / cleaning trade-off surface; and **generative AI** adds a governed,
human-supervised interpretation layer. Crucially, the AI is **never** treated as
ground truth and **never** controls the process.

## 3. Requirements

- **MATLAB R2026a** (developed and intended for this release).
- **Required toolboxes**
  - Simulink (mechanistic model + `parsim`/`Simulink.SimulationInput`)
  - Statistics and Machine Learning Toolbox (`fitrensemble`)
  - Global Optimization Toolbox (`gamultiobj`)
- **Optional toolboxes (graceful fallback if missing)**
  - Parallel Computing Toolbox → enables `parsim`; otherwise serial `sim`
  - Stateflow → optional phase logic; otherwise a MATLAB Function scheduler
  - Deep Learning Toolbox → not required by the default pipeline
- **Optional, for the live AI layer**
  - Environment variable `GEMINI_API_KEY` (and optionally `GEMINI_MODEL`,
    default `gemini-3.5-flash`). A project `.env` is also supported (canonical or
    `VITE_*`-prefixed names). Without a key the AI layer runs in the
    **Deterministic Offline Reproduction Mode**.
  - Set `CIP_GEMINI_MODE=mock` to activate the **Deterministic Offline
    Reproduction Mode** for fully reproducible, network-free public-release regeneration.

## 4. How to run

```matlab
% From the project root in MATLAB:
cd('<project_root>')
addpath('src')

% Full study (>= 5000 scenarios):
run('src/run_full_pipeline.m')

% Quick public-release smoke test:
setenv('CIP_GEMINI_MODE','mock'); setenv('CIP_N_SCENARIOS','50'); run('src/run_full_pipeline.m')

% Live Gemini (optional):
setenv('GEMINI_API_KEY','your-key-here'); run('src/run_full_pipeline.m')
```

The pipeline order is: scenario generation → validation → surrogate training →
policy translation → Pareto optimization → dataset summary → plausibility audit
→ Pareto explanation → figure/table artifact generation → run manifest.

> The Simulink model `model/dairy_cip_digital_twin.slx` must exist before
> running scenarios. It is constructed/maintained via the MATLAB agentic toolkit.

## 5. Expected outputs

| Location | Artifact |
|---|---|
| `data/` | `dairy_cip_synthetic_dataset.csv` (inputs + outputs + `simulation_status`) |
| `results/` | `dataset_validation_report.txt`, `surrogate_models.mat` (generated locally on run), `surrogate_metrics.csv` |
| `results/` | `selected_policy_config.json`, `pareto_solutions.csv`, `dataset_summary.json` |
| `results/` | `plausibility_audit.json`, `gemini_decision_report.txt` |
| `results/` | `run_manifest.json` (row counts, fingerprints, Gemini mode, pipeline status) |

*Note: direct manuscript text, styling code, and publication figures/tables folders are excluded from Git and generated manually via Python scripts locally.*


## 6. ⚠️ Synthetic-data warning

Every dataset, metric, figure and report is derived from a **simplified
simulation** with **uncalibrated, proof-of-concept coefficients** (see
`src/cip_parameters.m`). Do **not** interpret any number as a real industrial
measurement, and do **not** use any recipe operationally without industrial
calibration and food-safety validation.

## 7. Why Gemini is **not** used for real-time control

- **No ground truth.** An LLM cannot guarantee mass/energy balances or
  food-safety limits; it can hallucinate plausible-but-wrong values.
- **Safety.** CIP failures cause hygiene and product-safety risk; control must
  be deterministic and validated.
- **Separation of concerns.** Gemini is *never* called inside the Simulink solver
  or inside `gamultiobj`. It only (a) translates policy text → numeric
  constraints/weights, (b) audits summary statistics for human review, and
  (c) explains numerically-derived Pareto solutions after the fact.

## 8. Four-layer architecture

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │ Layer 1 — Simulink mechanistic digital twin                            │
 │   dairy_cip_digital_twin.slx : 4-phase CIP, first-order soil kinetics, │
 │   water/thermal/pump/COD/CO2/hygiene/EHPI models -> logsout            │
 ├──────────────────────────────────────────────────────────────────────┤
 │ Layer 2 — ML surrogate models                                          │
 │   fitrensemble regressors trained on the SYNTHETIC dataset to predict  │
 │   water_L, total_energy_kWh, COD_mgL, CO2eq_kg, cleaning_score, EHPI   │
 ├──────────────────────────────────────────────────────────────────────┤
 │ Layer 3 — Pareto multi-objective optimization                          │
 │   gamultiobj over the surrogates: minimize water/energy/COD/CO2,       │
 │   maximize cleaning, subject to a hygiene floor (cleaning >= 95)       │
 ├──────────────────────────────────────────────────────────────────────┤
 │ Layer 4 — Generative-AI decision support (Gemini) — GOVERNED           │
 │   (a) policy text -> constraints/weights (JSON)                        │
 │   (b) plausibility audit of summary stats (flags for humans)          │
 │   (c) post-optimization management explanation                         │
 │   NEVER inside the solver or optimizer; NEVER ground truth             │
 └──────────────────────────────────────────────────────────────────────┘
```

## 9. Repository layout

```
project_root/
  model/   dairy_cip_digital_twin.slx        (built reproducibly by src/build_model.m)
  src/     cip_parameters.m  cip_model_params.m   (central params; codegen-safe split)
           build_model.m                      (constructs the .slx from the params)
           gemini_call.m  load_dotenv.m       (Gemini HTTP helper; .env loader)
           run_cip_scenarios.m  validate_outputs.m  train_surrogate_models.m
           optimize_cip_pareto.m  build_dataset_summary.m
           gemini_policy_translator.m  gemini_plausibility_auditor.m
           gemini_explain_pareto.m  run_full_pipeline.m
  data/    dairy_cip_synthetic_dataset.csv
  results/ (metrics, pareto, json/txt reports)
  docs/    README.md  methodology_note.md  limitations_note.md
           public_release_manifest.md
```

> **First-time setup:** if `model/dairy_cip_digital_twin.slx` is absent, build it
> once with `run('src/build_model.m')` (Stateflow is optional — a MATLAB Function
> scheduler is used when it is unavailable). `run_full_pipeline.m` loads the model
> if present and warns if it must be built first.

## 10. Status

This is a **proof-of-concept simulation framework** prepared for later
calibration and manuscript development. See `docs/methodology_note.md` and
`docs/limitations_note.md`.

## 11. Agentic AI-supervised digital twin extension

The framework is extended from a system where Gemini only *translates policy,
audits summaries and explains the Pareto front* into an **AI-supervised,
closed-loop digital twin** for sustainable dairy CIP optimization — while
keeping the governance strict.

> **Scientific framing.** This project implements an AI-supervised,
> self-explaining digital twin for sustainable dairy CIP decision support. The
> generative-AI layer is extended beyond post-hoc explanation to support
> hypothesis generation, active simulation design, model plausibility auditing,
> policy formalization, virtual supervisory control recommendation, and
> traceable human-in-the-loop decision dossiers. **Direct real-time process
> control is explicitly excluded** until calibration with industrial data,
> microbiological validation, and certified safety constraints are available.

**What the generative-AI layer may do** (governed): propose **experiments**,
**hypotheses**, **policies**, **candidate scenarios** and **explanations**.

**What it must never do:** control a real process; run inside the Simulink
solver; run inside `gamultiobj`; act as ground truth. Every numeric decision is
made by **deterministic MATLAB code**; every recommended setpoint passes a
**deterministic safety gate**; **human approval is mandatory**; all outputs are
labelled **simulation-generated synthetic data**.

### New modules

| Module | Role |
|---|---|
| `gemini_hypothesis_generator.m` | AI proposes falsifiable, testable hypotheses → `results/ai_hypotheses.json` |
| `validate_ai_hypotheses.m` | **Deterministic** (no Gemini) correlation/regression tests → `results/ai_hypothesis_validation.csv` |
| `gemini_experiment_designer.m` | AI proposes candidate scenarios; MATLAB clamps to `P.lb/P.ub` → `results/ai_experiment_design.json` |
| `run_ai_designed_scenarios.m` | Simulates the AI-designed deck on the Simulink twin → `data/dairy_cip_ai_designed_dataset.csv` |
| `build_model_equation_summary.m` | Textual equations + constants + expected relations → `results/model_equation_summary.json` |
| `gemini_model_auditor.m` | AI flags model-structure concerns for humans → `results/model_audit_report.json` (no parameter change) |
| `ai_supervisory_control_recommender.m` | **Virtual** supervisory recommendation behind a deterministic safety gate → `results/ai_supervisory_recommendation.json` |
| `cip_policy_profiles.m` | Single source of truth for the six operational policy profiles |
| `build_run_manifest.m` | Reproducibility/consistency manifest → `results/run_manifest.json` |
| `build_ai_decision_dossier.m` | Traceable human-in-the-loop dossier → `results/ai_decision_dossier.md` (+ `.json`) |

### New drivers (the classic `run_full_pipeline.m` is left stable)

```matlab
addpath('src')
run('src/run_ai_closed_loop_study.m')   % agentic closed loop in the twin (N=3)
run('src/run_policy_portfolio.m')        % same plant, six context-dependent recipes
run('src/build_ai_decision_dossier.m')   % aggregate a traceable decision dossier
```

The **closed loop** (per iteration) chains: dataset summary → hypothesis
generation → experiment design → AI-scenario simulation → hypothesis validation
→ model audit → surrogate retraining on the *combined* (base + AI-designed)
dataset → Pareto optimization → virtual supervisory recommendation, writing
`results/ai_closed_loop_trace.json`.

### The deterministic safety gate

A recommended recipe is **rejected** if `cleaning_score` is below the policy
hygiene floor, if any finite policy cap (`max_COD_mgL`, `max_water_L`,
`max_total_energy_kWh`, `max_CO2eq_kg`, `max_hygienic_risk`) is exceeded, or if
any input is outside `P.lb/P.ub`. The whole recommendation is marked
`research_only` when a safety-critical surrogate has held-out R² below
`P.surrogate_r2_floor` (0.90) or when the model audit reports unresolved
HIGH-severity flags. Gemini only *explains* the (already decided) recommendation.

### Graceful degradation

Every Gemini module runs without `GEMINI_API_KEY` in the clearly-labelled
**Deterministic Offline Reproduction (MOCK)** mode and locally
validates/sanitizes the returned JSON, so malformed or truncated LLM responses
fall back to **Deterministic Offline Template Output** instead of crashing. The `run_manifest.json` records whether each artifact was produced
`LIVE` or `MOCK` (and flags `MIXED` runs).
