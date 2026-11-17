<!-- Author: Ketney Otto
     Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
     Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154 -->

# Counterfactual CIP Study (what-if interventions)

> SIMULATION-GENERATED SYNTHETIC surrogate predictions over the digital twin.
> NOT real plant responses; screening/hypothesis use only. Human approval required.

**Baseline recipe:** T_C=78.3 C, Q=1.84 m3/h, t_pre=565, t_alk=1777, t_int=185, t_final=663 s, NaOH=2.40%, heat_rec=0.55, water_rec=0.58 (soil0=0.50 fixed).

## Effect of each intervention (mean prediction; delta vs baseline)

| Intervention | cleaning | clean_lb | dClean | water_L | dWater | energy | dEnergy | COD | dCOD | CO2eq | dCO2 | hyg_risk | feasible |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| baseline | 99.8 | 99.1 | +0.0 | 686 | +0 | 34.70 | +0.00 | 22 | +0 | 6.76 | +0.00 | 0.036 | yes |
| t_alk_-10% | 99.8 | 99.1 | -0.0 | 685 | -1 | 33.60 | -1.10 | 22 | -0 | 6.71 | -0.06 | 0.038 | yes |
| t_alk_-20% | 99.8 | 98.9 | -0.0 | 669 | -16 | 29.61 | -5.08 | 22 | -0 | 5.86 | -0.90 | 0.051 | yes |
| T_C_+3C | 99.8 | 99.2 | +0.0 | 686 | +0 | 33.89 | -0.80 | 22 | +0 | 6.83 | +0.07 | 0.030 | yes |
| T_C_+5C | 99.8 | 99.2 | +0.0 | 686 | +0 | 34.25 | -0.45 | 22 | +0 | 6.77 | +0.01 | 0.031 | yes |
| water_rec_+0.15 | 99.8 | 99.1 | +0.0 | 685 | -0 | 34.70 | +0.00 | 22 | +0 | 6.76 | +0.00 | 0.036 | yes |
| NaOH_pct_-20% | 99.8 | 99.1 | -0.0 | 685 | -1 | 34.75 | +0.05 | 22 | +0 | 6.77 | +0.00 | 0.038 | yes |
| T_C_+5C_&_t_alk_-15% | 99.8 | 99.2 | +0.0 | 684 | -2 | 32.48 | -2.22 | 22 | +0 | 6.37 | -0.39 | 0.038 | yes |
| water_rec_+0.15_&_T_C_+3C | 99.8 | 99.2 | +0.0 | 686 | +0 | 33.89 | -0.80 | 22 | +0 | 6.83 | +0.07 | 0.031 | yes |

### Applied interventions (after clamping to bounds)
The labels above are the *requested* change; values are clamped to P.lb/P.ub, so the *realized* change may be smaller:
- `baseline`: (baseline)
- `t_alk_-10%`: t_alk: 1777->1599 (-177.7)
- `t_alk_-20%`: t_alk: 1777->1421 (-355.3)
- `T_C_+3C`: T_C: 78.3->81.3 (+3)
- `T_C_+5C`: T_C: 78.3->83.3 (+5)
- `water_rec_+0.15`: water_rec: 0.5782->0.6 (+0.0218)
- `NaOH_pct_-20%`: NaOH_pct: 2.4->1.92 (-0.48)
- `T_C_+5C_&_t_alk_-15%`: T_C: 78.3->83.3 (+5); t_alk: 1777->1510 (-266.5)
- `water_rec_+0.15_&_T_C_+3C`: water_rec: 0.5782->0.6 (+0.0218); T_C: 78.3->81.3 (+3)

**Best compromise (feasible, max burden reduction while holding hygiene):** `t_alk_-20%`.

### Interpretation
- Raising temperature (T_C) tends to raise cleaning but also energy/CO2.
- Shortening the alkaline phase (t_alk) saves time/energy but can lower cleaning.
- Higher water recovery (water_rec) cuts water with little hygiene cost.
- Lower NaOH reduces chemical load but may reduce cleaning and effluent COD.
- Feasibility is decided by the deterministic safety_shield on CONSERVATIVE bounds: an intervention is feasible only if it clears the FULL active policy - the 95% hygiene floor on the cleaning_score lower bound AND every finite cap (COD/water/energy/CO2/hygienic_risk) on the relevant upper bound. A recipe whose mean meets the floor but whose interval dips below it, or that breaches any cap, is marked NOT feasible.

_Counterfactuals predicted by ML surrogates of the mechanistic twin. Re-simulate with run_ai_designed_scenarios for exact mechanistic effects; calibrate before any real use._