# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""E48 - Test of the calibrated removal laws on a whey-protein-isolate gel cleaned in another laboratory (no refit).

Source (CC BY 4.0): Aselmeyer, F., Wiese, H., Hitzmann, O., Wu, X., Luks, T., Augustin, W., Scholl, S. (2026).
Comparative analysis of cleaning kinetics for whey protein gels in micro- and macroscale flow channels. Food and
Bioproducts Processing 159, 517-530. https://doi.org/10.1016/j.fbp.2026.07.012
Values quoted from the text (Sections 2.1, 2.3 and 3.2): gel of 0.15 g WPI/g, initial thickness 0.52 +/- 0.03 mm;
0.125 M NaOH (about 0.5 wt%); mean channel temperature 45.21 +/- 1.61 degC; macroscale channel (free height 7.5-8 mm),
superficial velocity 0.12 +/- 0.01 m/s; total cleaning time (fitted rate below 0.01 g m-2 s-1, including induction and
swelling) 720.5 s with three sample plates and 733.2 s with one.

Prediction: the uniform-removal law (M0) and the first-order law (M1) calibrated on the eight curves of Zhang et al.
(2025) (E16_calibrated_rate_law.json), evaluated at 45.21 degC (5 degC below the calibrated range) and 12 cm/s without
any refit; M0: time to remove the whole layer, h0 / r; M1: times to 90% and 99% removal. Parameter uncertainty:
20,000 draws from the jackknife covariance (fixed seed). Single condition, different soil (an isolate gel, not a
heat-induced deposit), different laboratory and channel: a transfer test, not a validation within the calibrated domain.

Output: ../outputs/E48_external_gel_test.json
"""
import json
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "outputs")
cal = json.load(open(os.path.join(OUT, "E16_calibrated_rate_law.json")))
T, V, H0 = 45.21, 12.0, 0.52                      # degC, cm/s, mm
OBS = {"three plates": 720.5, "one plate": 733.2}  # s


def rate(c, T, v, lnref=None, a=None, b=None):
    lnref = np.log(c["ref"]) if lnref is None else lnref
    a = c["alpha_per_degC"] if a is None else a
    b = c["beta"] if b is None else b
    return np.exp(lnref) * np.exp(a * (T - cal["T_ref_C"])) * (v / cal["v_ref_cm_s"]) ** b


def main():
    rng = np.random.default_rng(48)
    res = dict(source="Aselmeyer et al. (2026) FBP 159:517-530, doi:10.1016/j.fbp.2026.07.012",
               conditions=dict(T_degC=T, v_cm_s=V, h0_mm=H0, NaOH="0.125 M"), observed_total_time_s=OBS)
    for model in ("M0", "M1"):
        c = cal[model]
        P = rng.multivariate_normal([np.log(c["ref"]), c["alpha_per_degC"], c["beta"]],
                                    np.array(c["jackknife_cov_lnref_alpha_beta"]), 20000)
        r = rate(c, T, V)
        rs = rate(c, T, V, P[:, 0], P[:, 1], P[:, 2])
        if model == "M0":
            t = H0 / r * 60.0
            ts = H0 / rs * 60.0
            res[model] = dict(law="uniform removal", predicted_time_to_complete_removal_s=float(t),
                              parameter_interval_95_s=[float(x) for x in np.percentile(ts, [2.5, 97.5])],
                              ratio_pred_obs={k: float(t / o) for k, o in OBS.items()},
                              obs_inside_parameter_interval=bool(all(np.percentile(ts, 2.5) <= o <= np.percentile(ts, 97.5)
                                                                    for o in OBS.values())))
        else:
            t90, t99 = np.log(10) / r * 60.0, np.log(100) / r * 60.0
            res[model] = dict(law="first order", predicted_t90_s=float(t90), predicted_t99_s=float(t99),
                              ratio_t90_to_obs_total={k: float(t90 / o) for k, o in OBS.items()},
                              parameter_interval_95_t90_s=[float(x) for x in
                                                           np.percentile(np.log(10) / rs * 60.0, [2.5, 97.5])])
    json.dump(res, open(os.path.join(OUT, "E48_external_gel_test.json"), "w"), indent=2)
    print(json.dumps(res, indent=2))


if __name__ == "__main__":
    main()
