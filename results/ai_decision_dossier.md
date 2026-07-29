<!-- Author: Ketney Otto
     Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
     Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154 -->

# AI Decision Dossier — Dairy CIP Self-Explaining Digital Twin

> ⚠️ **SIMULATION-GENERATED SYNTHETIC DATA.** Proof-of-concept, uncalibrated.
> Decision **support** only — not a decision, not validated for plant use.

- **Run id:** `run_20260603_102118_8478`
- **Generated:** 2026-06-03 10:21:19
- **Scenarios (dataset rows):** 5000
- **Data source:** simulation-generated synthetic data (mechanistic Simulink twin, proof-of-concept)
- **Generative-AI mode:** MOCK (model: gemini-3.5-flash)

## Scientific framing
This project implements an AI-supervised, self-explaining digital twin for sustainable dairy CIP decision support. The generative-AI layer is extended beyond post-hoc explanation to support hypothesis generation, active simulation design, model plausibility auditing, policy formalization, virtual supervisory control recommendation, and traceable human-in-the-loop decision dossiers. Direct real-time process control is explicitly excluded until calibration with industrial data, microbiological validation, and certified safety constraints are available.

## 1. Surrogate accuracy (held-out)
| Target | R² |
|---|---|
| water_L | 0.993 |
| total_energy_kWh | 0.992 |
| COD_mgL | 0.997 |
| CO2eq_kg | 0.992 |
| cleaning_score | 0.967 |
| EHPI | 0.984 |
| hygienic_risk | 0.911 |

## 2. AI-generated hypotheses
11 hypotheses proposed (source: MOCK_fallback).
- **H1** (negative, high): Higher water recovery reduces per-cycle water consumption.
- **H2** (positive, high): Reducing fresh water (higher water_rec) concentrates the effluent, raising COD_mgL.
- **H3** (negative, high): Heat recovery reduces total energy use.
- **H4** (negative, medium): Heat recovery reduces CO2-equivalent emissions.
- **H5** (positive, high): Longer alkaline-wash duration increases cleaning score.
- **H6** (positive, medium): Higher wash temperature increases cleaning score.
- **H7** (positive, medium): Higher NaOH concentration increases cleaning score.
- **H8** (negative, high): Higher initial soil load decreases cleaning score.
- **H9** (positive, high): Higher initial soil load should increase effluent COD.
- **H10** (positive, medium): Higher temperature increases total energy use.
- **H11** (negative, medium): EHPI rewards low-burden recipes: it rises as water use falls.

## 3. Deterministic hypothesis validation (MATLAB, no Gemini)
supported=10, partially=0, not_supported=1, inconclusive=0 (of 11).
- H1: **supported** (r=-0.451)
- H2: **not_supported** (r=0.005)
- H3: **supported** (r=-0.413)
- H4: **supported** (r=-0.413)
- H5: **supported** (r=0.398)
- H6: **supported** (r=0.335)
- H7: **supported** (r=0.193)
- H8: **supported** (r=-0.447)
- H9: **supported** (r=0.976)
- H10: **supported** (r=0.318)
- H11: **supported** (r=-0.839)

## 4. Model audit (human review required)
High-severity flags: **0** (source: MOCK_fallback). Parameters were NOT modified.
- [MEDIUM] **cleaning_score / hygienic_risk proxies** — cleaning_score and hygienic_risk are derived only from residual soil; they are not microbiological measurements.

## 5. Active policy
- **Profile:** balanced_default — Balanced default operation
- **Risk tolerance:** medium
- **Min cleaning score:** 95

## 6. Virtual supervisory recommendation
- **Safety gate passed:** yes
- **Research-only:** yes
- **Human approval required:** yes
- **Not for real-time control:** yes
- **Candidates passing gate:** 149 / 149

**Manager summary.** 
[MOCK] For the balanced_default context, the safety gate accepted 149 of 149 candidate recipes and selected one meeting the hygiene floor (predicted cleaning 99.8%). This recommendation is RESEARCH-ONLY due to surrogate/model-audit caveats. Human approval is required; figures are synthetic.

**Engineer summary.** 
[MOCK] The selected recipe cleared all HARD deterministic checks (input bounds, hygiene floor and any finite environmental/hygienic caps) under conservative bounds. Critical surrogate R^2 are reported on the "uncertainty_conservative" basis and compared to the 0.90 floor; not all necessarily pass. Research-only advisories: Critical surrogate R^2 below 0.90 (uncertainty_surrogate_metrics): cleaning_score. This recommendation is RESEARCH-ONLY due to surrogate/model-audit caveats. Verify against plant data first.

## 6b. Surrogate uncertainty (quantile regression forests)
| Target | R² | 90% coverage | mean interval width |
|---|---|---|---|
| cleaning_score | 0.860 | 0.993 | 8.923 |
| COD_mgL | 0.988 | 1.000 | 9.519 |
| water_L | 0.963 | 0.995 | 529.9 |
| total_energy_kWh | 0.948 | 0.993 | 21.63 |
| CO2eq_kg | 0.950 | 0.993 | 4.325 |
| hygienic_risk | 0.913 | 0.996 | 0.5855 |
_Surrogate uncertainty over the simulator, NOT measurement uncertainty._

## 6c. Deterministic safety shield
- **Shield gate passed:** yes (basis: uncertainty_conservative)
- **Research-only:** yes
- No hard violations on the selected recipe.
- **Research-only advisories (why it is not deployment-ready):**
  - Critical surrogate R^2 below 0.90 (uncertainty_surrogate_metrics): cleaning_score
- The shield is MANDATORY: AI/Gemini cannot bypass it; human approval still required.

## 6d. Robust (uncertainty-aware) Pareto
- Robust front solutions: 149 (min cleaning lower-bound on front: 95.026%).
- Selection uses CONSERVATIVE bounds (cleaning q05, COD/hygienic q95) and penalizes high uncertainty.

## 6e. Counterfactual alternatives
**Best compromise intervention:** `t_alk_-20%`.
| Intervention | applied (after clamp) | cleaning | dClean | dWater | dEnergy | dCOD | feasible |
|---|---|---|---|---|---|---|---|
| baseline | (baseline) | 99.8 | +0.00 | +0 | +0.00 | +0 | yes |
| t_alk_-10% | t_alk: 1777->1599 (-177.7) | 99.8 | -0.01 | -1 | -1.10 | -0 | yes |
| t_alk_-20% | t_alk: 1777->1421 (-355.3) | 99.8 | -0.02 | -16 | -5.08 | -0 | yes |
| T_C_+3C | T_C: 78.3->81.3 (+3) | 99.8 | +0.01 | +0 | -0.80 | +0 | yes |
| T_C_+5C | T_C: 78.3->83.3 (+5) | 99.8 | +0.01 | +0 | -0.45 | +0 | yes |
| water_rec_+0.15 | water_rec: 0.5782->0.6 (+0.0218) | 99.8 | +0.00 | -0 | +0.00 | +0 | yes |
| NaOH_pct_-20% | NaOH_pct: 2.4->1.92 (-0.48) | 99.8 | -0.00 | -1 | +0.05 | +0 | yes |
| T_C_+5C_&_t_alk_-15% | T_C: 78.3->83.3 (+5); t_alk: 1777->1510 (-266.5) | 99.8 | +0.00 | -2 | -2.22 | +0 | yes |
| water_rec_+0.15_&_T_C_+3C | water_rec: 0.5782->0.6 (+0.0218); T_C: 78.3->81.3 (+3) | 99.8 | +0.01 | +0 | -0.80 | +0 | yes |
_Labels are the REQUESTED change; "applied (after clamp)" is the realized change after clamping to bounds (e.g. water_rec_+0.15 may clamp to a smaller delta)._

## 7. Limitations
- Uncalibrated proof-of-concept coefficients; synthetic data only.
- Effluent COD is an organic-load proxy tied to cumulative soil removal, not a measured laboratory COD assay.
- cleaning_score is a soil-based proxy, not a microbiological measurement.
- EHPI is a proposed index, not a regulatory standard.
- Gemini cannot verify mass/energy balances; it is never ground truth.
- Not for operational control without calibration and food-safety validation.

## 8. Real data required before any operational use
- Industrial CIP operating logs for coefficient calibration.
- Microbiological / ATP measurements to validate cleaning_score.
- Time-resolved effluent COD to fix the COD sub-model.
- Certified food-safety / HACCP constraints.
- Time-resolved effluent COD per CIP phase.
- Initial soil load (soil0) proxy and post-clean residual soil / ATP.
- Inlet/outlet temperatures and thermal energy for heat-recovery validation.
- Water flow and recovered-water fraction per phase.

## 9. Run consistency
- No consistency warnings.

---
_Generated by build_ai_decision_dossier.m. Gemini is decision support, never ground truth; numeric decisions are made by deterministic MATLAB code; human approval is mandatory._