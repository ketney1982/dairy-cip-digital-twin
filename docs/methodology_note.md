<!-- Author: Ketney Otto
     Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
     Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154 -->

# Methodology Note

**Project:** Self-Explaining Digital Twin for Environmental Decision Support in Dairy CIP Systems.

> All quantitative results are **simulation-generated synthetic data**. The
> empirical coefficients are **proof-of-concept assumptions** centralized in
> `src/cip_parameters.m` and must be calibrated before any scientific or
> operational claim.

---

## 1. System boundary

The model represents **only the CIP cleaning cycle** of a single dairy line — not
the full dairy plant, not the product process, and not the downstream wastewater
treatment works. Inputs are the CIP operating conditions; outputs are
per-cycle environmental burdens and a hygiene proxy.

## 2. CIP phases

A simplified four-phase cycle is modeled, with an integer `phase_id`:

| `phase_id` | Phase |
|---|---|
| 0 | idle |
| 1 | pre-rinse |
| 2 | alkaline wash |
| 3 | intermediate rinse |
| 4 | final rinse |
| 5 | end |

Phase scheduling is time-driven from the phase durations `t_pre`, `t_alk`,
`t_int`, `t_final`. If Stateflow is available the transitions PRE_RINSE →
ALKALINE_WASH → INTERMEDIATE_RINSE → FINAL_RINSE → END may be implemented as a
chart; otherwise an equivalent **MATLAB Function** scheduler based on simulation
time `t` is used (the default, dependency-free implementation).

> **Implementation note (this build).** The model is built reproducibly from
> `src/build_model.m` as a visual top-level Simulink architecture with these
> inspectable subsystems: `Scenario Inputs`, `Phase Scheduler`, `Soil Removal
> Kinetics`, `Water Consumption`, `Thermal Energy`, `Pump Energy`, `Wastewater
> and COD`, `Hygiene and Risk`, `EHPI and Output Metrics`, and `Logging and
> Scopes`. The phase scheduler uses a Stateflow chart when available; otherwise
> `build_model.m` falls back to an equivalent MATLAB Function scheduler. Recipe
> variables are exposed through labelled Constant blocks and automated runs
> override them with `Simulink.SimulationInput.setVariable(...,'Workspace',mdl)`,
> never base-workspace `assignin`. All function blocks call the codegen-safe
> numeric parameter file `src/cip_model_params.m`, which `src/cip_parameters.m`
> re-exports, so the model and the analysis scripts share a single coefficient
> source.

## 3. Mechanistic assumptions

- **Soil removal (first-order kinetics):** `dsoil/dt = -k·soil`, with a
  phase-specific rate `k` (each scaled by the global calibration factor
  `k_cal`, see note below):
  - pre-rinse: `k = k_cal·k_pre_base·(Q/Q_ref)^β_Q`
  - alkaline wash: `k = k_cal·k_alk_base·exp(α_T·(T−T_ref))·(Q/Q_ref)^β_Q·(NaOH/NaOH_ref)^γ_NaOH`
  - intermediate/final rinse: `k = k_cal·k_rinse_base·(Q/Q_ref)^β_Q`
  - idle/end: `k = 0`
  Soil is integrated from `soil0` and clamped to be non-negative.
- **Organic COD** is proportional to the cumulative mass proxy of soil removed:
  `COD_mgL = COD_factor·max(soil0−soil,0)`. This intentionally makes effluent
  organic COD respond to the initial soil load and the finite cleaning kinetics,
  rather than to an instantaneous removal-rate average.
- **Chemical COD-equivalent** is reported separately as
  `COD_chem_equiv_mgL = COD_chemical_factor·NaOH_residual_mgL`. Inorganic NaOH
  residual is **not** added to `COD_mgL`; `COD_mgL` is kept as an organic-load
  proxy.
- **NaOH residual** is a phase-dependent surrogate of carry-over
  (alkaline ≫ intermediate > final ≫ 0).
- **Water consumption** integrates the flow during active phases reduced by
  recovery: `water_L_s = (Q·1000/3600)·(1−water_rec)`.
- **Thermal energy** (alkaline wash only, MVP): `m_dot·cp·ΔT/η_heater`, reduced
  by `(1−heat_rec)`, integrated and converted to kWh.
- **Pump energy** during active phases: `(ΔP·Q_m3s/η_pump)/1000`, integrated to kWh.
- **CO₂-equivalent:** `thermal_kWh·EF_thermal + pump_kWh·EF_electricity`.
- **Hygiene proxies:** `cleaning_score = clamp((1−soil)·100, 0, 100)`;
  `hygienic_risk = clamp(soil/0.05, 0, 1)`.
- **EHPI (proposed index):**
  `EHPI = 100·cleaning_norm / (1 + 0.25·(water_norm+energy_norm+COD_norm+CO2_norm))`,
  where each term is normalized by the constants in `cip_parameters.m`.
  **EHPI is a proposed synthetic environmental–hygienic index, not an industrial
  standard.**

### Empirical coefficients (initial proof-of-concept values)

| Group | Constants |
|---|---|
| Kinetics | `k_cal=0.08` (global), `k_pre_base=0.030`, `k_alk_base=0.010`, `k_rinse_base=0.006`, `T_ref=60`, `alpha_T=0.035`, `beta_Q=0.45`, `gamma_NaOH=0.60`, `Q_ref=1.5`, `NaOH_ref=1.0` |
| COD | `COD_factor=45`, `COD_chemical_factor=0.15` |
| Thermal | `rho=1000`, `cp=4.186`, `eta_heater=0.85` |
| Pump | `deltaP=180000`, `eta_pump=0.60` |
| Emissions | `EF_electricity=0.25`, `EF_thermal=0.20` |
| Hygiene | `min_cleaning_score=95`, `max_hygienic_risk=1.0` |
| EHPI norm. | `norm_water_L=500`, `norm_energy_kWh=20`, `norm_COD_mgL=5000`, `norm_CO2eq_kg=10` |

#### Kinetic calibration factor `k_cal`

The base rate constants specified for the proof of concept (`k_pre_base`,
`k_alk_base`, `k_rinse_base`, in s⁻¹) combined with realistic phase durations of
hundreds to thousands of seconds drive the dimensionless decay exponent `k·t`
into the range ≈13–27. Under first-order kinetics this annihilates essentially
all soil in **every** scenario, saturating `cleaning_score` at 100 % (standard
deviation ≈10⁻⁴) — the "model too easy" degenerate case that `validate_outputs`
is explicitly designed to detect, and which would collapse the
cleaning-vs-environment trade-off that the study exists to expose.

A single transparent calibration factor `k_cal` multiplies all three base rates
identically, **preserving the exact equation structure and the specified ratios
between the phase rates**. Its value (`k_cal = 0.08`) was selected by analytic
Monte-Carlo over the full parameter ranges so that `cleaning_score` spans a
meaningful range (mean ≈94.5 %, standard deviation ≈6 %, with roughly 60 % of
scenarios satisfying the 95 % hygiene floor). This makes the hygiene constraint
actually bind during optimization. `k_cal` is itself a proof-of-concept knob and
must be re-estimated together with the base rates from plant or literature data.

## 4. Synthetic data generation

Scenarios are sampled by **Monte-Carlo** (uniform within the ranges below,
`rng(42)`), configured with `Simulink.SimulationInput` (no `assignin`), and
executed with `parsim` + **Fast Restart** when the Parallel Computing Toolbox is
present, falling back to serial `sim`. Failed runs are retained with a
`simulation_status` column.

| Variable | Range | Unit |
|---|---|---|
| `T_C` | 45–85 | °C |
| `Q_m3h` | 0.5–3.0 | m³/h |
| `t_pre` | 120–600 | s |
| `t_alk` | 300–1800 | s |
| `t_int` | 120–600 | s |
| `t_final` | 180–900 | s |
| `NaOH_pct` | 0.5–2.5 | % |
| `soil0` | 0.1–1.0 | – |
| `heat_rec` | 0.0–0.7 | – |
| `water_rec` | 0.0–0.6 | – |
| `T_in_C` | 15 (fixed) | °C |

## 5. Surrogate modeling

For each target (`water_L`, `total_energy_kWh`, `COD_mgL`, `CO2eq_kg`,
`cleaning_score`, `EHPI`) a `fitrensemble` (LSBoost) regressor is trained on an
80/20 split (`rng(42)`). Accuracy is reported as **R², RMSE, MAE, MAPE** on the
held-out set (`results/surrogate_metrics.csv`) with predicted-vs-observed plots.
These surrogates approximate the **simulator**, not reality.

## 6. Optimization

Multi-objective Pareto optimization (`gamultiobj`, with a non-dominated sampling
fallback) over the surrogates: minimize `water_L`, `total_energy_kWh`, `COD_mgL`,
`CO2eq_kg` and `-cleaning_score`, subject to `cleaning_score ≥ 95` (or a stricter
policy value). **`soil0` is treated as an uncertainty condition, not an operator
setpoint** (`FIX_SOIL0 = true` by default); operators control only
`T_C, Q_m3h, t_pre, t_alk, t_int, t_final, NaOH_pct, heat_rec, water_rec`.
Policy-derived objective weights are used only for **post-hoc** balanced-solution
selection, never inside the optimizer.

## 7. Generative AI (governed)

- **Policy → constraints translator** (`gemini_policy_translator.m`): natural
  language → strict JSON (`min_cleaning_score ≥ 95`, weights summing to 1). No
  setpoints.
- **Plausibility auditor** (`gemini_plausibility_auditor.m`): inspects the
  compact dataset summary and flags suspicious patterns for **human review**. No
  recalibration.
- **Post-optimization explainer** (`gemini_explain_pareto.m`): explains the
  numeric trade-offs of selected Pareto scenarios for managers.

All three call Gemini only through `gemini_call.m`, read the key from
`GEMINI_API_KEY`, and fall back to clearly-labelled **mock** outputs when no key
is configured. Gemini is **never** invoked inside Simulink or `gamultiobj`.

## 8. Limitations

No industrial validation yet; empirical coefficients require calibration;
simplified wastewater chemistry; no microbiological validation of `cleaning_score`;
no full life-cycle assessment (LCA). See `limitations_note.md`.

## 9. Future work

Calibration with plant data; integration of real sensors; real-time model
predictive control (MPC); a wastewater-treatment module; and an expanded LCA
boundary.

## 9b. Agentic AI-supervised digital twin extension

The generative-AI layer is extended from *post-hoc* support (policy translation,
plausibility audit, Pareto explanation) into an **AI-supervised closed loop that
operates entirely inside the digital twin** (never the plant). The governance
contract is unchanged and strengthened: Gemini **proposes**; deterministic
MATLAB **validates and decides**; a **safety gate** gates every recommendation;
**human approval is mandatory**; nothing is real-time control.

**Closed loop** (`run_ai_closed_loop_study.m`, default 3 iterations). Each
iteration: (1) build the compact dataset summary; (2) `gemini_hypothesis_generator`
proposes falsifiable hypotheses; (3) `gemini_experiment_designer` proposes
candidate scenarios that MATLAB clamps to `P.lb/P.ub`; (4) `run_ai_designed_scenarios`
simulates them on the Simulink twin; (5) `validate_ai_hypotheses` tests the
hypotheses **deterministically**; (6) `gemini_model_auditor` flags model-structure
concerns for humans (no parameter change); (7) surrogates are **retrained on the
combined** base + AI-designed dataset; (8) the Pareto front is recomputed;
(9) `ai_supervisory_control_recommender` issues a virtual, gated recommendation.
A JSON trace (`results/ai_closed_loop_trace.json`) records, per iteration, what
the AI proposed, what the gate accepted, what the simulator ran, which
hypotheses were supported, how the recommendation changed, and what remains
uncertain.

**Hypothesis validation** (`validate_ai_hypotheses.m`, no Gemini). Each
hypothesis lists dataset columns in `variables_involved` with the primary
predictor first and the outcome last. The script computes the Pearson
correlation (with p-value) of the primary predictor vs the outcome and a
simple/multiple linear regression (partial effect of the primary predictor),
then assigns `supported` / `partially_supported` / `not_supported` /
`inconclusive` by comparing the observed sign and strength with the stated
`expected_direction`. A "supported" verdict means the relation holds **in the
simulator**, not in a real plant.

**Model auditing** (`build_model_equation_summary.m` → `gemini_model_auditor.m`).
The equation summary states each governing equation textually, lists the
`cip_model_params` constants, the input ranges and output definitions, and the
**expected qualitative relations**. In this build, `soil0 → COD_mgL` is expected
to be positive because organic COD is based on cumulative soil removed, while
`NaOH_pct → COD_mgL` is only indirect through cleaning kinetics; NaOH residual
is reported separately. The auditor flags concerns and proposes
experiments/measurements; it never edits a parameter.

**Policy profiles** (`cip_policy_profiles.m`, `gemini_policy_translator.m`). Six
operational profiles — `balanced_default`, `water_scarcity`,
`energy_price_spike`, `cod_discharge_limit`, `carbon_reduction`,
`hygiene_priority` — define constraints (with unconstrained caps emitted as JSON
`null`, never `[]`) and objective weights summing to 1. `run_policy_portfolio.m`
shows that the *same* surrogate-defined achievable envelope yields *different*
recommended recipes per context.

**Virtual supervisory control** (`ai_supervisory_control_recommender.m`). The
deterministic safety gate rejects any Pareto candidate below the hygiene floor,
above any finite policy cap (`max_COD_mgL`, `max_water_L`,
`max_total_energy_kWh`, `max_CO2eq_kg`, `max_hygienic_risk`), or outside
`P.lb/P.ub`. **Division of responsibility (by design):** `gamultiobj` enforces
only `min_cleaning_score` and `max_COD_mgL` so it yields one broad,
policy-agnostic Pareto front; the remaining caps are applied *downstream* — per
candidate by the safety gate, and as filters in `run_policy_portfolio` — so many
policies can select and gate from the same front without re-optimizing. The recommendation is marked `research_only` when a safety-critical
surrogate has held-out R² below `P.surrogate_r2_floor` (0.90) or when the model
audit reports unresolved HIGH-severity flags. To enforce a numeric
`max_hygienic_risk`, `hygienic_risk` was added to `P.targets` and a surrogate is
trained for it. Gemini only explains the already-decided recommendation; it
cannot override the gate or set a value.

**Traceability** (`build_run_manifest.m`, `build_ai_decision_dossier.m`). A run
manifest records a run id, row counts, lightweight file fingerprints, the Gemini
*model name* (never the key), and whether artifacts are LIVE/MOCK/MIXED, with
consistency warnings (e.g. dataset-vs-summary row mismatch, a stuck pipeline
sentinel). The decision dossier aggregates everything a human reviewer needs.

## 9c. Uncertainty-aware robust layer, safety shield, and counterfactuals

This extension reframes the system as a **digital twin with AI supervisory
control, uncertainty-aware robust optimization, and a deterministic safety
shield** (run end-to-end by `run_innovation_pipeline.m`). The distinct methods,
and how they differ, are:

- **Pareto optimization** (`optimize_cip_pareto.m`): multi-objective search over
  the **mean** surrogate predictions, subject to the hygiene floor (and COD cap).
  Produces a trade-off front of *expected* performance.
- **Uncertainty-aware surrogates** (`train_uncertainty_surrogates.m`): quantile
  regression forests (`TreeBagger` + `quantilePredict`) give a lower (q05),
  median (q50) and upper (q95) prediction per critical target, with reported
  interval **coverage** (fraction of held-out points inside the 90% interval) and
  mean width. These quantify SURROGATE uncertainty over the simulator — not
  measurement uncertainty.
- **Robust Pareto** (`optimize_cip_robust_pareto.m`): optimizes over
  **conservative bounds** (cleaning q05 ≥ floor, COD/hygienic q95 ≤ caps) and
  penalizes high-uncertainty recipes, so the chosen recipes remain feasible under
  surrogate uncertainty — unlike the mean-based Pareto front.
- **AI policy translation** (`gemini_policy_translator.m`): maps natural-language
  policy to JSON constraints and **five** objective weights (hygienic_risk is a
  hard constraint, not a weight). Gemini proposes; MATLAB validates/sanitizes.
- **AI supervisory recommendation** (`ai_supervisory_control_recommender.m`):
  ranks front candidates by the policy weights and selects the best one that also
  clears the safety shield; Gemini only *explains* the already-decided result.
- **Safety shield** (`safety_shield.m`): an INDEPENDENT, deterministic gate on a
  single recipe. It re-checks input bounds and the policy caps using
  **conservative** uncertainty bounds, flags low surrogate R² and unresolved
  HIGH-severity model-audit issues as `research_only`, and has **veto power** — a
  recipe it rejects cannot be reported as gate-passed. The AI cannot bypass it.
- **Closed-loop feedback** (`run_ai_closed_loop_study.m`): the agentic loop —
  AI proposes hypotheses/experiments, the twin simulates them, MATLAB validates
  and audits, surrogates retrain on the growing combined dataset, the front is
  recomputed, and a gated recommendation is issued. Distinct from the one-shot
  pipeline in that the dataset and surrogates evolve across iterations.
- **Counterfactual analysis** (`run_counterfactual_cip_study.m`): controlled
  "what-if" interventions (e.g. `t_alk` −10/−20%, `T_C` +3/+5 °C, more
  `water_rec`, less `NaOH_pct`) and their predicted effect on every target, with
  uncertainty intervals and a feasibility check against the hygiene floor. This
  probes input→output sensitivity of the twin, complementing the optimization.

Governance is unchanged: Gemini proposes experiments/hypotheses/policies/
explanations; deterministic MATLAB decides; the safety shield gates; human
approval is mandatory; nothing is real-time control; all data are synthetic and
require experimental calibration before operational interpretation.

## 10. Figure captions

- **`fig_pareto_water_energy.png`** — Pareto-efficient recipes in the water–energy
  plane, colored by cleaning score (synthetic).
- **`fig_pareto_cod_cleaning.png`** — COD vs cleaning-score trade-off across the
  Pareto front, colored by energy (synthetic).
- **`fig_sensitivity_temperature.png`** — Cleaning score vs wash temperature
  (scatter + binned-mean trend) over the synthetic scenarios.
- **`fig_sensitivity_naoh.png`** — Cleaning score vs NaOH concentration
  (scatter + binned-mean trend).
- **`fig_correlation_heatmap.png`** — Pearson correlation heatmap of key inputs
  and outputs in the synthetic dataset.

## 11. Revision R1 analyses (Journal of Food Engineering)

The analyses added in the first revision use the existing layout: scripts in
`src/`, outputs in `results/`. The original pipeline (sections 1–10) is unchanged.
In the revised manuscript the system is called a *simulation framework* (a
digital model in the sense of Kritzinger et al., 2018), because it has no
automated data exchange with a physical plant; file names containing
`digital_twin` are kept for continuity of published links.

### Closed-form simulator

Because `k_phase` is constant within each phase, `dS/dt = -k_phase(t) S` has the
exact solution

```
S(t_end) = s0 * exp(-(k_pre t_pre + k_alk t_alk + k_rinse (t_int + t_final)))
```

and every other output is an integral of a piecewise-constant rate.
`src/cip_closed_form.py` implements this solution with the coefficients of
`src/cip_model_params.m` and the variable names and bounds of
`src/cip_parameters.m`, which it parses directly from these MATLAB files (no
values are repeated in Python); the EHPI penalty weight 0.25, which is not
defined in these files, is the fixed weight of the `output_metrics` block
generated by `src/build_model.m` and the named constant `LAMBDA_EHPI` in the
Python module. It reproduces the 5,000 Simulink scenarios with
R² > 0.9999 and makes direct Monte Carlo auditing on the simulator possible.

### Scripts and outputs

| Script | Outputs in `results/` | Manuscript items |
|---|---|---|
| `src/verify_closed_form.py` | `closed_form_vs_simulink.csv`, `timing_closed_form.json` | Eq. (4a); Table S11 |
| `src/run_robustness_audit.py` | `policy_recipes_unrounded.json`, `policy_recipes_nominal_surrogate_vs_simulator.csv`, `policy_recipes_MC_audit.csv`, `CS_draws.npz`, `candidate_level_admission_and_selection.csv`, `candidate_q10.npz`, `uncertainty_sets.json`, `kcal_central_sensitivity.csv` | Tables 3–5, S7, S9, S13; Fig. 5 |
| `src/run_counterfactual_closed_form.py` | `counterfactual_closed_form.csv` | Table S4; Fig. S4 |
| `src/run_audit_benchmarks.py` | `audit_deterministic_benchmarks.csv`, `pareto_front_audit.csv`, `mc_threshold_stability.csv`, `structural_sensitivity.csv` | Table 5 (deterministic benchmarks); Tables S14 (Pareto front), S15 (structural sensitivity), S16 (Monte Carlo stability) |
| `src/run_threshold_sensitivity.py` | `threshold_quantile_sensitivity.csv`, `water_energy_fronts_nominal_vs_robust.csv`, `candidates_quantiles.npz` | Table S10; Figs. 6, S8 |
| `src/run_sobol_sensitivity.py` | `sobol_indices.csv` | Table S12; Fig. S7 |
| `src/validate_surrogates_extended.m` | `surrogate_5fold_cv.csv`, `surrogate_random_and_region_splits.csv`, `surrogate_vs_simulator_MC_audit_U0.csv`, `timing_matlab.csv`, `surrogate_validation_log.txt` | Table 2, Tables S8, S11; Fig. S9 |
| `src/qrf_prediction_intervals.m` | `QRF_PI_coverage_base5000.csv` | Table 2 (prediction intervals) |
| `src/trace_original_table4_audit.m` | `QRF_trace_of_original_Table4.csv` | response to reviewers (R1.28) |

The outputs contain the data underlying every table and figure of the revised
manuscript.

`candidate_level_admission_and_selection.csv` also contains a minimum-velocity
screen (rows `*_min_velocity`): mean velocity of at least 1.5 m/s in the
22.2-mm internal-diameter reference tube, i.e. Q >= 2.09 m3/h, combined with
the nominal caps and the q0.10(CS) >= 95% audit (column `velocity_m_s` gives the
velocity of every selected recipe). `kcal_central_sensitivity.csv` repeats the
candidate-level and policy-recipe audits with the central value of the kinetic
scaling factor `k_cal` set to 0.06-0.10 (the U3 log-normal spread is kept around
the new centre; the policy recipes are held fixed).

`run_counterfactual_closed_form.py` applies nine local what-if interventions
(one or two setpoints changed, clamped to the Table 1 bounds) to the
balanced-default policy recipe of main Table 3 (`policy_recipes_unrounded.json`),
evaluates them with the closed-form simulator at s0 = 0.5 and audits each
intervened recipe under U0 and U3. The original `run_counterfactual_cip_study.m`
used a baseline taken from the exploratory AI-supervisory layer
(`ai_supervisory_recommendation.json`) and surrogate (quantile-regression-forest)
predictions, which are not constrained by the water and energy balances (e.g.
lower energy for a hotter wash at fixed flow and duration); its output
`counterfactual_cip_results.csv` is kept for traceability only.

`run_audit_benchmarks.py` (run after `run_robustness_audit.py`) writes four
checks of the audit:

- `audit_deterministic_benchmarks.csv`: because CS decreases linearly with s0
  (Eq. 4a), q0.10(CS) under U0 equals the nominal CS at the 90th percentile of
  the soil-load distribution (s0 = 0.91); the candidate audit is compared with
  deterministic design-load checks at s0 = 0.91 and 1.0 and with a conservative
  corner (s0 = 0.91, k_cal at its 10th percentile under U3, 0.0581): number of
  admitted candidates, agreement with the U3 audit and the selected recipe.
- `pareto_front_audit.csv`: the 76 recipes of the `gamultiobj` front
  (`pareto_solutions.csv`) re-simulated at s0 = 0.5 and audited under U0 and U3
  (M = 10,000, common random numbers as in Table 4).
- `mc_threshold_stability.csv`: the candidate audit repeated with independent
  seeds at M = 1,000 and M = 10,000; verdict changes, near-threshold counts,
  re-selected recipes and distribution-free 95% intervals of q0.10(CS) for the
  selected recipes (from the original M = 1,000 draws and from the independent
  M = 10,000 audit, for the original and the re-selected recipes).
- `structural_sensitivity.csv`: ratio k_pre,base / k_alk,base of 0.5, 1, 2 and 3
  (nominal) and triangular or beta distributions of s0 instead of the uniform
  one.

**Admission filter versus `safety_shield.m`.** The admission verdicts of the
revised manuscript (Tables 4 and 5, Figs. 5 and 6) are produced by the
simulator-level filter of `run_robustness_audit.py` (nominal caps with simulator
values at s0 = 0.5, then q0.10(CS) >= 95% on the Monte Carlo distribution of the
simulator). `src/safety_shield.m` is the single-recipe gate of the earlier
surrogate-based supervisory pipeline (Section 9c): it uses conservative
quantile-regression-forest bounds at s0 = 0.5 (q0.05 of CS, q0.95 of capped
outputs) and no Monte Carlo propagation. The two procedures represent different
uncertainties and their verdicts are not interchangeable.

### Figures: underlying data

The plotting scripts are not distributed (graphical layout only); each data
figure is a direct plot of the following tracked files. Fig. 1 is an
explanatory schematic without data.

| Figure | Underlying files |
|---|---|
| Fig. 2 | `data/dairy_cip_synthetic_dataset.csv` |
| Fig. 3 | `results/surrogate_pred_vs_obs.csv` |
| Fig. 4 | `results/pareto_solutions.csv` |
| Fig. 5 | `results/CS_draws.npz`, `results/policy_recipes_MC_audit.csv` |
| Fig. 6 | `results/candidates_quantiles.npz`, `results/water_energy_fronts_nominal_vs_robust.csv`, `results/threshold_quantile_sensitivity.csv`, `results/candidate_level_admission_and_selection.csv`, `results/policy_recipes_unrounded.json` |
| Fig. S1 | `results/demo_timeseries_baseline.csv` |
| Figs. S2, S3 | `data/dairy_cip_synthetic_dataset.csv` |
| Fig. S4 | `results/counterfactual_closed_form.csv` (baseline: balanced-default recipe) |
| Fig. S5 | `results/policy_portfolio_results.csv` |
| Fig. S6 | `results/figS1_phase_summary.csv` |
| Fig. S7 | `results/sobol_indices.csv` |
| Fig. S8 | `results/threshold_quantile_sensitivity.csv` |
| Fig. S9 | `results/surrogate_random_and_region_splits.csv`, `results/surrogate_5fold_cv.csv` |

The feasible-candidate counts of Fig. S5 (e.g. 17,299 for the balanced
default, 1,917 for hygiene priority) come from the original surrogate-based
screening; `candidate_level_admission_and_selection.csv` re-evaluates the same
30,000 candidates with the simulator (18,006 and 2,314), so the two sets of
counts differ by evaluator, not by policy definition. In `sobol_indices.csv`, a
few first-order estimates are slightly negative or slightly larger than the
total-effect estimate (e.g. EHPI, `water_rec`); these are Monte Carlo
estimation errors of the Saltelli/Jansen estimators.

### Uncertainty sets of the robustness audit

| Set | Uncertain quantities |
|---|---|
| U0 | initial soil load s0 ~ U(0.1, 1.0) |
| U1 | U0 + T ~ N(T_set, 1.5 °C); Q and c_NaOH × (1 + N(0, 0.05)) |
| U2 | U1 + inlet-water temperature T_in ~ U(5, 25 °C) |
| U3 | U2 + k_cal ~ logN(ln 0.08, 0.25); α_T ~ N(0.035, 0.007); β_Q ~ N(0.45, 0.09); γ_NaOH ~ N(0.60, 0.12) |

A recipe is admitted if q0.10(CS) ≥ 95 %. This is the only probabilistic
rejection criterion and it is the same for all policy profiles; the
policy-specific caps (e.g. R_hyg ≤ 0.1 for hygiene priority) are applied at
nominal conditions. The 30,000-candidate policy envelope and the original
5,000-scenario design are regenerated exactly from MATLAB `rng(42)`
(`cip_closed_form.matlab_rand`).

Two additional checks are written by `src/run_robustness_audit.py`:

- *Policy cap in the upper tail.* `policy_recipes_MC_audit.csv`, column
  `policy_Rhyg_cap_met_q90`, states whether the hygiene-priority recipe also
  meets q0.90(R_hyg) ≤ 0.1 (it does not: 0.14–0.36). In
  `candidate_level_admission_and_selection.csv`, the screenings
  `U0_with_Rhyg_cap` and `U3_with_Rhyg_cap` add this condition to the
  audit-then-select filter of the hygiene-priority profile; `candidate_q10.npz`
  holds the candidate-level q0.90(R_hyg) (`Rhyg_q90_U0`, `Rhyg_q90_U3`).
- *Setpoint errors at the bounds.* In U1–U3 the realised T, Q and c_NaOH can
  leave the Table 1 bounds (setpoints near 85 °C or 2.5 %). The column
  `frac_draws_outside_bounds` gives the share of such draws; the columns
  `CS_q10_bounded`, `Rhyg_q90_bounded` and `admitted_bounded`, the screenings
  `U0_bounded` and `U3_bounded` and the arrays `U0_bounded`, `U3_bounded` repeat
  the audit with the realised values truncated to the bounds.

### Reproduction

Python 3.11 with the pinned `requirements.txt`; MATLAB R2026a with Simulink and the
Statistics and Machine Learning Toolbox.

```bash
cd src
python verify_closed_form.py
python run_robustness_audit.py
python run_audit_benchmarks.py
python run_counterfactual_closed_form.py
python run_threshold_sensitivity.py
python run_sobol_sensitivity.py
matlab -batch "validate_surrogates_extended"
matlab -batch "qrf_prediction_intervals"
matlab -batch "trace_original_table4_audit"
```

Seeds: MATLAB `rng(42)` (design, splits), NumPy 2026 (Monte Carlo audits), 7
(Sobol samples); `run_audit_benchmarks.py` uses the independent seeds 2127 and
2228 for the Monte Carlo stability check. The Python scripts reproduce the files
in `results/` to floating-point precision (differences of the order of 1e-13 can
occur between NumPy versions or platforms); only the timing files depend on the
computer.
