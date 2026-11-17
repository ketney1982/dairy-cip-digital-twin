<!--
Author: Ketney Otto
Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
             Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
             550012 Sibiu, Romania
Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154
-->

# Revision R2 – benchmark against published experimental cleaning data

Analyses added in the second revision of *A safety-governed simulation framework for auditing the
robustness of Pareto-optimal cleaning-in-place recipes in dairy processing* (Journal of Food
Engineering). The removal kinetics are benchmarked against published cleaning curves, the
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
| `e17_calibrated_case_audit.py` | Monte Carlo audit of the calibrated case (30,000 candidates; U0–U3; uniform-removal and first-order law); required wash times; retrospective check against the measured curves, with the full calibration and cross-validated | `E17_summary.json`, `E17_selected_recipes.csv`, `E17_selected_recipes_U0_U3.csv`, `E17_fronts.csv`, `E17_required_wash_time.csv`, `E17_retrospective_check.csv`, `E17_retrospective_check_crossvalidated.csv`, `E17_retrospective_summary.csv`, `E17_retrospective_crossvalidated_summary.csv` | Section 3.2; Table 4; Fig. 3; Suppl. Tables S22, S23, S25 |
| `e18_anchored_sensitivity_illustrative_case.py` | Re-audits the illustrative pipe-circuit case with experimentally anchored kinetics (9 parameterisations); uses `src/cip_closed_form.py`, `data/` and `results/policy_recipes_unrounded.json` | `E18_anchored_sensitivity.csv` | Section 3.4; Suppl. Table S24 |

| `e24_tests_beyond_calibration_data.py` | Tests made after the calibration had been fixed: curve at 75 °C in the same apparatus (Zhang et al., 2026), with the audit rule applied to the unseen condition; cleaning times of a laboratory plate heat exchanger; plateau removal fluxes of two other laboratories; published sensitivities | `E24_summary.json`, `E24_digitised_Zhang2026.csv`, `E24_axis_calibration.csv`, `E24_plate_heat_exchanger_test.csv`, `E24_plateau_flux_other_laboratories.csv`, `E24_published_sensitivities.csv` | Sections 2.4 and 3.1; Table 3; Suppl. Section S6, Tables S26–S27, Fig. S13 |

`e17` also writes `outputs/E17_candidates.csv` (all 30,000 audited candidates, 3.5 MB); it is regenerated by the
script and is not stored in the repository.

## Reproduce

Python 3.11 with the pinned `requirements.txt` of the repository (NumPy, SciPy, pandas, Pillow).

```
cd revision_R2/scripts
python e15_digitise_published_cleaning_data.py
python e16_experimental_benchmark.py
python e17_calibrated_case_audit.py
python e18_anchored_sensitivity_illustrative_case.py
python e24_tests_beyond_calibration_data.py
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
- Cross-validated comparison with the 16 measured curves: the observed cleaning score is below the 95% floor in 6
  curves at the nominal wash time, in 5 at the time for thickness variation alone and in none at the time for the
  full uncertainty set. This is a consistency test on the data set that supplied the kinetics, not an independent
  validation.
- Tests made after the calibration had been fixed: a curve at 75 °C and 23.65 cm/s (5 °C above the calibrated range) was predicted
  with a predicted-to-observed time to 90% removal of 0.73 (uniform removal) and 1.19 (first order); at the nominal wash time and at
  the time for thickness variation alone the measured curve was below the floor, at the time for the full uncertainty set the deposit
  had been removed. For a laboratory plate heat exchanger the flat-channel law underestimates the alkaline cleaning time 11–25-fold.
  For the deposits of two other laboratories the calibrated rate exceeds the reported plateau removal fluxes by a factor of 1.2–2.7.
- Illustrative pipe-circuit case with experimentally anchored kinetics: the verdicts of individual recipes change;
  the nominally selected recipe is rejected in all 9 parameterisations.

## Limits

Published laboratory data digitised from figures or quoted from tables; calibration on one deposit type, 0.5 wt% NaOH, 50–70 °C and
velocities up to 0.23 m/s; the kinetic parameters did not transfer to other soils or to a plate heat exchanger; no industrial installation.
