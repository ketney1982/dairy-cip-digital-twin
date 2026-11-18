# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""E57 - Two checks of the consolidation of the second revision (no new kinetic data).

A. Pipe-circuit case: all six policy profiles (caps and weights of Supplementary Table S6) selected nominally from the
   30,000-candidate envelope with the original weights and with the CODorg weight set to zero (the other weights
   renormalised), on simulator values at s0 = 0.5, and audited under U3: stored candidate audit (M = 1,000) and an
   independent re-audit of every selected recipe (M = 10,000, seed of src/run_conservative_selection.py, lower limit of
   the distribution-free 95% interval).
B. The prescription of the audit applied to the two external data sets of E48/E49 (other laboratories, not used for
   calibration): the margin of the robust wash time over the nominal one under U3 (E17_required_wash_time.csv, uniform-
   removal law, at the calibrated condition nearest to the external one) multiplied by the predicted-to-observed time
   ratio of the nominal prediction; also with the margin divided by that of the thickness variation alone (U3/U0), which
   removes the deposit-thickness spread of the calibrated case. A value >= 1 means that the time prescribed under U3 would have been at least the
   measured cleaning time.

Inputs : ../../results/candidate_q10.npz, ../outputs/E17_required_wash_time.csv, E48_external_gel_test.json,
         E49_full_cycle_segment_tests.csv
Outputs: ../outputs/E57_profiles_without_CODorg.csv, ../outputs/E57_external_audit.csv, ../outputs/E57_summary.json
"""
import json
import os
import sys

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "outputs")
RES = os.path.join(HERE, "..", "..", "results")
sys.path.insert(0, os.path.join(HERE, "..", "..", "src"))
FLOOR = 95.0

# Supplementary Table S6: caps and weights (water, energy, CODorg, carbon, CS)
PROFILES = {
    "balanced default": (lambda Y: Y["cleaning_score"] >= 95, [0.20, 0.20, 0.20, 0.20, 0.10]),
    "water scarcity": (lambda Y: (Y["cleaning_score"] >= 95) & (Y["water_L"] <= 600), [0.40, 0.10, 0.15, 0.10, 0.15]),
    "energy-price spike": (lambda Y: (Y["cleaning_score"] >= 95) & (Y["total_energy_kWh"] <= 20), [0.10, 0.40, 0.10, 0.20, 0.10]),
    "COD-weighted": (lambda Y: (Y["cleaning_score"] >= 95) & (Y["COD_mgL"] <= 700), [0.15, 0.10, 0.40, 0.10, 0.15]),
    "carbon reduction": (lambda Y: (Y["cleaning_score"] >= 95) & (Y["CO2eq_kg"] <= 4), [0.10, 0.25, 0.10, 0.35, 0.10]),
    "cleaning priority": (lambda Y: (Y["cleaning_score"] >= 98) & (Y["hygienic_risk"] <= 0.1), [0.10, 0.10, 0.15, 0.10, 0.55]),
}


def select(Y, mask, w):
    """Lowest weighted sum of min-max normalised objectives (as in src/run_robustness_audit.py)."""
    idx = np.where(mask)[0]

    def nz(v):
        v = v[idx]
        s = v.max() - v.min()
        return (v - v.min()) / (s if s > 0 else 1)

    w = np.asarray(w, float) / np.sum(w)
    sc = (w[0] * nz(Y["water_L"]) + w[1] * nz(Y["total_energy_kWh"]) + w[2] * nz(Y["COD_mgL"])
          + w[3] * nz(Y["CO2eq_kg"]) + w[4] * (1 - nz(Y["cleaning_score"])))
    return int(idx[np.argmin(sc)])


def part_A():
    from cip_closed_form import LB, UB, matlab_rand                         # noqa: E402
    from run_robustness_audit import draws                                    # noqa: E402
    from run_conservative_selection import q10_with_interval, SEED_RECHECK    # noqa: E402
    z = np.load(os.path.join(RES, "candidate_q10.npz"))
    Y = {k: z[k] for k in ["water_L", "total_energy_kWh", "COD_mgL", "CO2eq_kg", "cleaning_score", "hygienic_risk"]}
    q3 = z["U3"]
    rows = []
    for prof, (cap, w) in PROFILES.items():
        for tag, ww in (("original weights", w), ("CODorg weight = 0", [w[0], w[1], 0.0, w[3], w[4]])):
            j = select(Y, cap(Y), ww)
            rows.append(dict(profile=prof, weights=tag, candidate=j, water_L=Y["water_L"][j],
                             energy_kWh=Y["total_energy_kWh"][j], CS_nominal=Y["cleaning_score"][j], q10_U3_M1000=q3[j]))
    df = pd.DataFrame(rows)
    Xc = LB + matlab_rand(42, 30000, 10) * (UB - LB)
    Xc[:, 7] = 0.5
    js = sorted(set(df.candidate))
    d = draws("U3", 10000, np.random.default_rng(SEED_RECHECK))
    q, ql, _ = q10_with_interval(Xc[js], d, chunk=len(js))
    m = {j: (q[i], ql[i]) for i, j in enumerate(js)}
    df["q10_U3_M10000"] = [m[j][0] for j in df.candidate]
    df["q10_lower_U3_M10000"] = [m[j][1] for j in df.candidate]
    df["admitted_U3"] = df.q10_lower_U3_M10000 >= FLOOR
    df.to_csv(os.path.join(OUT, "E57_profiles_without_CODorg.csv"), index=False, float_format="%.6g")
    return df


def part_B():
    req = pd.read_csv(os.path.join(OUT, "E17_required_wash_time.csv"))
    req = req[req.model == "M0"]

    def margin(T, v):
        """U3/nominal wash-time ratio at the calibrated condition nearest to (T, v) (T in 50-70 degC, v in 0.5-23 cm/s)."""
        Tn = min((50, 60, 70), key=lambda t: abs(t - T))
        vn = min(sorted(set(req.v_cm_s)), key=lambda x: abs(np.log(x) - np.log(v)))
        r = req[(req.T_C == Tn) & (req.v_cm_s == vn)].iloc[0]
        return Tn, vn, float(r.U3_over_nominal), float(r.U3_prediction_error_only_over_nominal), \
            float(r.U3_over_nominal / r.U0_over_nominal)

    rows = []
    gel = json.load(open(os.path.join(OUT, "E48_external_gel_test.json")))["M0"]
    for plates, ratio in gel["ratio_pred_obs"].items():
        Tn, vn, mu3, mpe, mnt = margin(45.21, 12.0)
        rows.append(dict(source="Aselmeyer et al. (2026), gel", condition=f"45 degC, 12 cm/s, {plates}", T_eval=45.21,
                         v_cm_s=12.0, nearest_calibrated=f"{Tn} degC, {vn} cm/s", nominal_ratio=ratio, margin_U3=mu3,
                         robust_ratio=ratio * mu3, margin_prediction_error_only=mpe, robust_ratio_pe_only=ratio * mpe,
                         margin_without_thickness=mnt, robust_ratio_without_thickness=ratio * mnt))
    e49 = pd.read_csv(os.path.join(OUT, "E49_full_cycle_segment_tests.csv"))
    g = e49[e49.segment.str.startswith("C") & e49.simulator_rate.str.startswith("calibrated")]
    for _, r in g.iterrows():
        Tn, vn, mu3, mpe, mnt = margin(r.T_eval, r.v_cm_s)
        rows.append(dict(source="Gillham et al. (2000), tubes", condition=r.condition, T_eval=r.T_eval, v_cm_s=r.v_cm_s,
                         nearest_calibrated=f"{Tn} degC, {vn} cm/s", nominal_ratio=r.ratio_pred_obs, margin_U3=mu3,
                         robust_ratio=r.ratio_pred_obs * mu3, margin_prediction_error_only=mpe,
                         robust_ratio_pe_only=r.ratio_pred_obs * mpe, margin_without_thickness=mnt,
                         robust_ratio_without_thickness=r.ratio_pred_obs * mnt))
    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(OUT, "E57_external_audit.csv"), index=False, float_format="%.4g")
    return df


def main():
    A, B = part_A(), part_B()
    gel = B[B.source.str.startswith("Aselmeyer")]
    t50 = B[B.source.str.startswith("Gillham") & (B.T_eval == 50) & (B.v_cm_s < 50)]
    t70 = B[B.source.str.startswith("Gillham") & (B.T_eval == 70) & (B.v_cm_s < 50)]
    hi = B[B.source.str.startswith("Gillham") & (B.v_cm_s > 50)]
    S = dict(
        profiles=dict(n=len(PROFILES),
                      admitted_U3_original=A[A.weights == "original weights"].set_index("profile").admitted_U3.to_dict(),
                      admitted_U3_without_CODorg=A[A.weights == "CODorg weight = 0"].set_index("profile").admitted_U3.to_dict(),
                      CS_without_CODorg=A[A.weights == "CODorg weight = 0"].set_index("profile").CS_nominal.round(2).to_dict(),
                      q10_lower_without_CODorg=A[A.weights == "CODorg weight = 0"].set_index("profile").q10_lower_U3_M10000.round(2).to_dict()),
        external=dict(gel_nominal=[float(gel.nominal_ratio.min()), float(gel.nominal_ratio.max())],
                      gel_robust=[float(gel.robust_ratio.min()), float(gel.robust_ratio.max())],
                      gel_robust_pe_only=[float(gel.robust_ratio_pe_only.min()), float(gel.robust_ratio_pe_only.max())],
                      gel_margin=float(gel.margin_U3.iloc[0]),
                      tubes_50C_nominal=[float(t50.nominal_ratio.min()), float(t50.nominal_ratio.max())],
                      tubes_50C_robust=[float(t50.robust_ratio.min()), float(t50.robust_ratio.max())],
                      gel_robust_without_thickness=[float(gel.robust_ratio_without_thickness.min()), float(gel.robust_ratio_without_thickness.max())],
                      tubes_50C_robust_without_thickness=[float(t50.robust_ratio_without_thickness.min()), float(t50.robust_ratio_without_thickness.max())],
                      tubes_70C_robust=[float(t70.robust_ratio.min()), float(t70.robust_ratio.max())],
                      tubes_92cms_robust=[float(hi.robust_ratio.min()), float(hi.robust_ratio.max())]))
    json.dump(S, open(os.path.join(OUT, "E57_summary.json"), "w"), indent=2)
    with pd.option_context("display.width", 250, "display.max_columns", 20):
        print(A.round(2).to_string(index=False))
        print(B.round(3).to_string(index=False))
    print(json.dumps(S, indent=2))


if __name__ == "__main__":
    main()
