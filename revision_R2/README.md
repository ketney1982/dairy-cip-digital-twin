<!--
Author: Ketney Otto
Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
             Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
             550012 Sibiu, Romania
Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154
-->

# Revision R2 – benchmark against published experimental cleaning data

Analyses added in the second revision of *A rule-governed simulation framework for auditing the
robustness of Pareto-optimal alkaline cleaning-in-place recipes in dairy processing, with the alkaline
removal kinetics tested against published data* (Journal of Food Engineering; first submitted as
*A safety-governed simulation framework for auditing the robustness of Pareto-optimal cleaning-in-place
recipes in dairy processing*). The removal kinetics are benchmarked against published cleaning curves, the
robustness audit is repeated on the experimentally calibrated model, and the wash times it
prescribes are compared with the measured curves.

## Data sources and licences

- Zhang, Y., van den Berg, F.W.J., Andersen, M.L., Portela, L.M., Parjikolaei, B.R., Bakalis, S. (2025).
  Cleaning in place of whey protein fouling - mechanisms of removal. *Journal of Food Engineering* 400, 112636.
  https://doi.org/10.1016/j.jfoodeng.2025.112636 (Figs. 6, 9 and 11; observations quoted from the text)
- Wiese, H., Geißler, H., Augustin, W., Scholl, S. (2024). Diffusive mass transfer and protein removal in the
  alkaline cleaning of a jellylike whey protein fouling layer. *Heat and Mass Transfer* 60, 829–840.
  https://doi.org/10.1007/s00231-023-03391-7 (Fig. 10a)

- Zhang, Y., van den Berg, F.W.J., Andersen, M.L., Parjikolaei, B.R., Bakalis, S. (2026).
  Cleaning in place of plate heat exchangers - Removal behavior of whey protein fouling. *Chemical Engineering Science* 320, 122395.
  https://doi.org/10.1016/j.ces.2025.122395 (Figs. 5, 8b and 9d)
- Single numerical results quoted, with citation, from Gillham et al. (1999, *Food Bioprod. Process.* 77, 127–136),
  Xin et al. (2004, *AIChE J.* 50, 1961–1973) and Tuladhar et al. (2002, *Food Bioprod. Process.* 80, 199–214).

**Third-party material.** The three digitised articles are open access under the Creative Commons Attribution 4.0 licence
(CC BY 4.0, https://creativecommons.org/licenses/by/4.0/). The figure images in `source_data/published_figures/` are unchanged
extracts of these articles; they remain the work of their authors and are redistributed here under CC BY 4.0 with the attribution,
copyright line and statement of changes given in `source_data/published_figures/_PROVENANCE.txt`. The digitised values in `outputs/`
(`E15_digitised_curves.csv`, `E24_digitised_Zhang2026.csv`) are adaptations of these figures made for this study and are likewise
available under CC BY 4.0; they are approximations of the plotted points, not the original measurements, and the original authors
have not reviewed or endorsed them. From the three articles that are not open access only individual numerical results are quoted,
with citation; no figure, table layout or text of these articles is reproduced, and the articles themselves are not distributed here.
No new experiments were performed.

## Content

| Script (`scripts/`) | What it does | Outputs (`outputs/`) | Manuscript |
|---|---|---|---|
| `e15_digitise_published_cleaning_data.py` | Digitises the published curves (colour segmentation; axis calibration on tick positions; no manual point picking) | `E15_digitised_curves.csv`, `E15_axis_calibration.csv`, `E15_published_scalar_observations.csv` | Section 2.4; Table 2; Suppl. Table S20 |
| `e16_experimental_benchmark.py` | Fits four removal laws to every curve; calibrates the rate law on 8 curves (jackknife, leave-one-condition-out); validates on 8 further curves and 1 independent laboratory | `E16_per_curve_fits.csv`, `E16_calibrated_rate_law.json`, `E16_leave_one_condition_out.csv`, `E16_validation_metrics.csv`, `E16_validation_summary.csv`, `E16_observed_vs_predicted.csv` | Section 3.1; Table 3; Fig. 2; Suppl. Tables S20–S21 |
| `e17_calibrated_case_audit.py` | Monte Carlo audit of the calibrated case (30,000 candidates; U0–U3; uniform-removal and first-order law); required wash times; retrospective check against the measured curves, with the full calibration and cross-validated. A measured curve is read only inside its record: for a wash time after the last measured point `observed_CS` and `observed_pass` are empty (`within_record` = False), the score of the last measured point is given in `last_measured_CS` and the time at which the curve first crossed the floor in `t_floor_crossing_obs_min` | `E17_summary.json`, `E17_selected_recipes.csv`, `E17_selected_recipes_U0_U3.csv`, `E17_fronts.csv`, `E17_required_wash_time.csv`, `E17_retrospective_check.csv`, `E17_retrospective_check_crossvalidated.csv`, `E17_retrospective_summary.csv`, `E17_retrospective_crossvalidated_summary.csv` | Section 3.2; Table 4; Fig. 3; Suppl. Tables S22, S23, S25 |
| `e18_anchored_sensitivity_illustrative_case.py` | Re-audits the illustrative pipe-circuit case with experimentally anchored kinetics (9 parameterisations); uses `src/cip_closed_form.py`, `data/` and `results/policy_recipes_unrounded.json` | `E18_anchored_sensitivity.csv` | Section 3.4; Suppl. Table S24 |

| `e24_tests_beyond_calibration_data.py` | Tests made after the calibration had been fixed: curve at 75 °C in the same apparatus (Zhang et al., 2026), with the audit rule applied to the unseen condition; cleaning times of a laboratory plate heat exchanger; plateau removal fluxes of two other laboratories; published sensitivities (the plate-heat-exchanger table flags NaOH, temperature, velocity and geometry against the calibrated domain separately; no condition lies inside it) | `E24_summary.json`, `E24_digitised_Zhang2026.csv`, `E24_axis_calibration.csv`, `E24_plate_heat_exchanger_test.csv`, `E24_plateau_flux_other_laboratories.csv`, `E24_published_sensitivities.csv` | Sections 2.4 and 3.1; Table 3; Suppl. Section S6, Tables S26–S27, Fig. S13 |
| `e26_R21_checks.py` | Audit restricted to the calibrated domain (extrapolation test) and composition of the robust margin; propagation of the digitisation error into the calibration (300 replicates); status of every curve in the retrospective check (wash time within or after the measured record) | `E26_A_domain_restricted_counts.csv`, `E26_A_domain_restricted_selected.csv`, `E26_A_wash_time_ratios.csv`, `E26_B_digitisation_replicates.csv`, `E26_B_digitisation_summary.json`, `E26_C_retrospective_status.csv` | Section 3.2; Suppl. Tables S23, S28, S29 |
| `e28_R22_checks.py` | Cleaning score at the last measured point of the curves whose audited wash time lies after the record; pipe-circuit case re-audited with a uniform-removal law in place of the first-order law | `E28_A_last_point_check.csv`, `E28_B_uniform_law_pipe_circuit.csv`, `E28_console.txt` | Sections 3.2 and 3.4; Suppl. Tables S23, S24 |
| `e29_decision_rule_comparison.py` | Calibrated case: the Monte Carlo audit compared with deterministic admission rules (nominal check, maximum deposit thickness, fixed margins on the wash time) on the same 30,000 candidates; reads the audit results of `e17`, no new simulation | `E29_decision_rule_comparison.csv` | Sections 3.2 and 4.1; Suppl. Table S32 |
| `e32_calibration_hull_check.py` | Calibrated case: nominal setpoints restricted to the convex hull of the eight calibration conditions in the plane (temperature, ln velocity), i.e. to the combinations of temperature and velocity covered by the calibration curves; nominal screening, non-dominated set and audit repeated on the candidates inside the hull; reads the audit results of `e17` | `E32_calibration_hull_counts.csv`, `E32_calibration_hull_selected.csv` | Section 3.2; Suppl. Section S5, Table S28 |
| `e37_two_stage_law_audit.py` | Calibrated case: spread of the two-stage parameters over the calibration curves; calibration of a lumped two-stage law (transition and rate ratio fixed at their medians, two variants) and repetition of the audit, the required wash times and the retrospective check (full calibration) with it; imports `e16` and `e17` | `E37_summary.json`, `E37_two_stage_audit.csv`, `E37_two_stage_parameter_spread.csv` | Sections 3.1 and 3.2; Table 1; Suppl. Section S5 |
| `e40_codorg_and_terminal_score_checks.py` | Pipe-circuit case: non-dominated set and policy selection with and without the organic-load proxy CODorg (which is a linear function of CS at s0 = 0.5), weight sensitivity, audit verdict by nominal CS band, dominance of the audit-then-select recipe; selected recipes re-audited with M = 10,000. Calibrated case: sensitivity of the retrospective check to the estimate of the terminal score (last point, last point - 2 sd of the digitisation error, last two points, mean of the last three points, interpolated crossing). Reads `results/candidate_q10.npz`, `results/pareto_front_audit.csv` and the outputs of `e16`/`e26` | `E40_A_fronts_without_CODorg.csv`, `E40_A_selection_without_CODorg.csv`, `E40_A_gamultiobj_front.csv`, `E40_B_terminal_score_sensitivity.csv`, `E40_summary.json`, `E40_console.txt` | Sections 2.5, 3.2, 3.3, 3.4; Suppl. Section S3.4, Tables S33-S34 |
| `e19_make_figures_R2.py`, `e27_fig3_R21.py` | Draw Figs. 2–3 and Suppl. Fig. S13 from the outputs above (the function `fig1` of `e19` draws an earlier schematic version of Fig. 1; the published Fig. 1 is an illustration that is not generated from data and is not part of the repository) | (figure files, not stored) | Figs. 2–3; Suppl. Fig. S13 |

`e17` also writes `outputs/E17_candidates.csv` (all 30,000 audited candidates, 3.5 MB); it is regenerated by the
script and is not stored in the repository; `e29` and `e32` read it, so `e17` has to be run first.

## Reproduce

Python 3.11 with the pinned `requirements.txt` of the repository (NumPy, SciPy, pandas, Pillow).

```
cd revision_R2/scripts
python e15_digitise_published_cleaning_data.py
python e16_experimental_benchmark.py
python e17_calibrated_case_audit.py
python e18_anchored_sensitivity_illustrative_case.py
python e24_tests_beyond_calibration_data.py
python e26_R21_checks.py
python e28_R22_checks.py
python e29_decision_rule_comparison.py
python e32_calibration_hull_check.py
python e37_two_stage_law_audit.py
python e40_codorg_and_terminal_score_checks.py
```

All random seeds are fixed; the scripts reproduce the stored outputs.

## Main results

- 17 distinct curves (16 from the flow channel, 1 from the independent laboratory). Median RMSE of the normalised
  residual soil: first order 0.086, first order with lag 0.050, uniform removal 0.037, two-stage 0.027.
- Uniform-removal law calibrated on 8 curves: r_ref = 0.157 mm/min at 70 °C and 1 cm/s, alpha_T = 0.070 /°C,
  beta_v = 0.35. Predicted-to-observed time to 90% removal: 0.78–1.19 for the 8 validation curves (measured at
  conditions contained in the calibration set) and 0.67–1.44 in leave-one-condition-out cross-validation; first-order
  law 1.36–2.04 and 1.24–2.60. For the independent laboratory (another soil, 23.5 °C) both laws are wrong by a factor
  of about 3.
- Calibrated case: none of the 23 nominally non-dominated recipes passes the audit; the audited wash time is 1.20
  (deposit thickness only) and 1.47–1.90 (full uncertainty set) times the nominal one.
- Cross-validated comparison with the 16 measured curves: the nominal wash time lies within the measured record of 8
  curves, of which 6 are below the 95% floor; the time for thickness variation alone lies within the record of 6, of
  which 5 are below the floor. The time for the full uncertainty set lies within the record of only 3 curves, all of
  which meet the floor; for the other 13 that time lies after the last measured
  point, at which 12 had already reached the floor (an inference, not an observation at the prescribed time) and one
  stood at 94.6%. Counted by the first crossing of the floor in the measured curve, 9, 10 and 15 of the 16 curves had
  crossed it by the nominal, thickness-only and full-uncertainty wash times. With the first-order law only 1, 1 and 0
  of the 16 prescribed times lie within the measured record. This is a consistency test on the data set that supplied
  the kinetics, not an independent validation.
- Combinations of temperature and velocity (`e32`): the calibration covers six velocities at 70 °C and two further
  temperatures at 1 cm/s. With the nominal setpoints restricted to the convex hull of these conditions in the plane
  (temperature, ln velocity), 14,953 of the 30,000 candidates remain, 11,798 of them nominally feasible; the nominal
  non-dominated set again has 23 recipes and none passes the audit.
- Kinetic structure (`e37`): fitted curve by curve, the two-stage law has its transition after 2–79% of the layer and
  a second-stage rate 0.37–5.53 times the first. With both fixed at their medians, the lumped two-stage law fits the
  calibration curves less well than uniform removal (RMSE 0.11–0.13 against 0.091) and predicts the time to 90% removal
  of the validation curves too short (median ratio 0.80–0.86); audited with it, none of the 20–22 nominally
  non-dominated recipes passes under the full uncertainty set, and one of the three curves whose record reaches its
  robust wash time is below the floor.
- Audit against deterministic rules on the same 30,000 candidates (`e29`): the nominal check admits 4,292 candidates
  that fail the audit under the full uncertainty set, a check at the maximum deposit thickness 2,510; a fixed margin
  of 1.5 on the nominally sufficient wash time still admits 614, and the smallest fixed margin without such
  admissions (1.88) rejects 1,965 candidates that pass.
- Tests made after the calibration had been fixed: a curve at 75 °C and 23.65 cm/s (5 °C above the calibrated range) was predicted
  with a predicted-to-observed time to 90% removal of 0.73 (uniform removal) and 1.19 (first order); at the nominal wash time and at
  the time for thickness variation alone the measured curve was below the floor, whereas the time for the full uncertainty set (5.9 min)
  lay after the last measured point (5.2 min) and was not observed; the measured curve crossed the floor at about 5.13 min (linear
  interpolation) and stood at 97.9% at its last point (mean of the last three points 94.2%). For a laboratory plate heat exchanger the flat-channel law underestimates the alkaline cleaning time 11–25-fold.
  For the deposits of two other laboratories the calibrated rate exceeds the reported plateau removal fluxes by a factor of 1.2–2.7.
- Illustrative pipe-circuit case with experimentally anchored kinetics: the verdicts of individual recipes change;
  the nominally selected recipe is rejected in all 9 parameterisations (balanced-default weights, which include CODorg).
- CODorg (`e40`): with it as an objective all 18,006 nominally feasible candidates of the pipe-circuit envelope are
  non-dominated; without it 97 are, of which the 38 with the lowest nominal CS fail under the full uncertainty set.
  No candidate with a nominal CS below 98% passes (0 of 9,372). With the CODorg weight set to zero, the balanced-default
  selection reaches CS = 98.9% and passes narrowly (q0.10 = 95.7%, lower limit 95.6%); a residual weight of 0.05 restores
  the rejection. Terminal score: of the 13 curves whose record ends before the robust wash time, 12 reach the floor by
  the last point, 11 by the last point less twice the digitisation error, 5 by the last two points and 4 by the mean of
  the last three points.

## Limits

Published laboratory data digitised from figures or quoted from tables; calibration on one deposit type, 0.5 wt% NaOH, 50–70 °C and
velocities up to 0.23 m/s; the kinetic parameters did not transfer to other soils or to a plate heat exchanger; no industrial installation.
