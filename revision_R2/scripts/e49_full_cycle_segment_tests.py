# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""E49 - The full-cycle simulator of the pipe-circuit case tested segment by segment against published data (no refit).

The closed-form simulator (src/cip_closed_form.py; parameters of src/cip_model_params.m, i.e. the ASSUMED parameters of
the illustrative case) and, where stated, the uniform-removal law calibrated in E16 are evaluated at the conditions of
published experiments. Velocities are mapped to the simulator through the flow rate that gives the same mean velocity
in its 22.2-mm reference tube. Only values quoted in the text or tables of the sources are used (no digitisation).

  A  pre-rinse, pipe: Fan, Phinney & Heldman (2015) J Food Sci 80(7):E1490-E1497, doi:10.1111/1750-3841.12914.
     Dried non-fat-milk film (75 degC, 30 min) in 22.2-mm i.d. stainless-steel pipe; tap water 22 degC, 20 s:
     residual film 26.9% at 0.72 m/s and 9.3% at 2.26 m/s (fit RF% = 41.68 exp(-0.68 v)); all temperatures and
     velocities at 20 s: 5.1-26.9%.
  B  water circulation and caustic stage, pilot test bed: Pant, Cotter, Wilkinson & Sheehan (2025) Int J Dairy Technol
     78(4) e70071, doi:10.1111/1471-0307.70071 (CC BY-NC-ND). Milk fouling (72 degC, 8 h) on coupons in a recirculating
     test bed, 4800 L/h, 30 min: residual fouling (dry matter) 26.88% with water at 19-22 degC, 13.98% at 50 degC,
     11.14% at 75 degC, 0.1% with 1% NaOH at 75 degC (0.21 +/- 0.17% in a second series). Pipe diameter not reported:
     evaluated for 22.2-50.8 mm, i.e. a mean velocity of 3.44-0.66 m/s.
  C  alkaline stage in tubes: Gillham, Fryer, Hasting & Wilson (2000) J Food Eng 46:199-209,
     doi:10.1016/S0260-8774(00)00083-2. Heat-induced whey-protein deposit in a 6-mm tube, 0.5 wt% NaOH, 50 degC, steady
     flow (Table 3): time to clean 12.0, 9.0, 7.0, 5.5 and 6.4 min at Re 1500 (139 and 108 g m-2), 2340 (91), 4680 (96)
     and 9120 (70 g protein m-2). Velocity from Re with the conversion of E24 (v = Re x 0.010077 cm/s).
  D  water balance, industrial CIP: Alvarez, Daufin & Gesan-Guiziou (2010) J Dairy Sci 93:808-821,
     doi:10.3168/jds.2009-2760, Table 1 (UHT tubular heat exchanger, initial and revised sequences): volume circulated
     per phase (flow x duration, the water use of a once-through cycle) against the effluent volume measured per phase.

Outputs: ../outputs/E49_full_cycle_segment_tests.csv, ../outputs/E49_summary.json
"""
import json
import os
import sys

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(HERE, "..", "outputs")
sys.path.insert(0, os.path.join(ROOT, "src"))
from cip_closed_form import P  # noqa: E402  (assumed parameters of the pipe-circuit case)

A_REF = np.pi / 4 * 0.0222 ** 2                     # m2, simulator reference tube
cal = json.load(open(os.path.join(OUT, "E16_calibrated_rate_law.json")))["M0"]
RHO_DRY = json.load(open(os.path.join(OUT, "E24_summary.json")))["C_plateau_flux"]["dry_matter_density_g_cm3"]
K_FLUX = RHO_DRY * 1e4 / 10.0 / 60.0                # mm/min -> g m-2 s-1


def q_sim(v):
    """Flow rate (m3/h) giving the mean velocity v (m/s) in the 22.2-mm reference tube."""
    return np.asarray(v) * A_REF * 3600.0


def k_phase(phase, v, T=None, naoh=None):
    fQ = (q_sim(v) / P["Q_ref"]) ** P["beta_Q"]
    if phase == "pre":
        return P["k_cal"] * P["k_pre_base"] * fQ
    if phase == "rinse":
        return P["k_cal"] * P["k_rinse_base"] * fQ
    return (P["k_cal"] * P["k_alk_base"] * np.exp(P["alpha_T"] * (T - P["T_ref"])) * fQ
            * (naoh / P["NaOH_ref"]) ** P["gamma_NaOH"])


def r_uniform(T, v_cm_s):
    return cal["ref"] * np.exp(cal["alpha_per_degC"] * (T - 70.0)) * v_cm_s ** cal["beta"]


rows = []
# ---------------------------------------------------------------- A  pre-rinse (Fan et al., 2015)
for v, obs in ((0.72, 26.9), (1.25, None), (1.67, None), (2.26, 9.3)):
    fit = 41.68 * np.exp(-0.68 * v)
    for t in (20.0, 60.0):
        for ph in ("pre", "rinse"):
            pred = 100 * np.exp(-k_phase(ph, v) * t)
            rows.append(dict(segment="A pre-rinse, pipe", source="Fan et al. (2015)", condition=f"22 degC, {v} m/s, {t:.0f} s",
                             simulator_rate=ph, quantity="residual film (%)", predicted=pred,
                             observed=obs if (obs is not None and t == 20.0) else (fit if t == 20.0 else np.nan),
                             observed_basis="quoted" if (obs is not None and t == 20.0) else ("authors' fit" if t == 20.0 else "")))
# ---------------------------------------------------------------- B  pilot test bed (Pant et al., 2025)
for d_mm in (22.2, 50.8):
    v = 4.8 / 3600.0 / (np.pi / 4 * (d_mm / 1000) ** 2)
    for med, T, naoh, obs in (("water", 20.5, None, 26.88), ("water", 50.0, None, 13.98), ("water", 75.0, None, 11.14),
                              ("1% NaOH", 75.0, 1.0, 0.1)):
        phases = ("rinse", "pre") if med == "water" else ("alk",)
        for ph in phases:
            k = k_phase(ph, v, T, naoh)
            rows.append(dict(segment="B pilot test bed, 30 min", source="Pant et al. (2025)",
                             condition=f"{med}, {T:g} degC, pipe {d_mm} mm (v = {v:.2f} m/s)", simulator_rate=ph,
                             quantity="residual fouling (%)", predicted=100 * np.exp(-k * 1800.0), observed=obs,
                             observed_basis="quoted"))
# ---------------------------------------------------------------- C  alkaline stage in tubes (Gillham et al., 2000)
# heat-flux rig: bulk 50 degC, heated block (wall) 70 degC; the deposit temperature lies between -> both bounds
for Re, cov, s in ((1500, 139, 12.0), (1500, 108, 9.0), (2340, 91, 7.0), (4680, 96, 5.5), (9120, 70, 6.4)):
    v_cm = Re * 0.010077
    for Td in (50.0, 70.0):
        k = k_phase("alk", v_cm / 100.0, Td, 0.5)
        t99 = np.log(100.0) / k / 60.0
        rows.append(dict(segment="C alkaline stage, 6-mm tube", source="Gillham et al. (2000)",
                         condition=f"0.5 wt% NaOH, T = {Td:g} degC, Re {Re} (v = {v_cm:.0f} cm/s), {cov} g m-2",
                         simulator_rate="alk", T_eval=Td, v_cm_s=v_cm,
                         quantity="time to clean (min); simulator: 99% removal", predicted=t99, observed=s,
                         observed_basis="quoted"))
        t_u = cov / (K_FLUX * r_uniform(Td, v_cm)) / 60.0
        rows.append(dict(segment="C alkaline stage, 6-mm tube", source="Gillham et al. (2000)",
                         condition=f"0.5 wt% NaOH, T = {Td:g} degC, Re {Re} (v = {v_cm:.0f} cm/s), {cov} g m-2",
                         simulator_rate="calibrated uniform-removal law (E16)", T_eval=Td, v_cm_s=v_cm,
                         quantity="time to clean (min); law: complete removal", predicted=t_u, observed=s,
                         observed_basis="quoted"))
# ---------------------------------------------------------------- D  water balance (Alvarez et al., 2010)
alv = {"initial": [("flushing-first rinse", 13.6, (2000 + 6053) / 2, 450, "rinse"), ("NaOH-1", 18.2, 6615, 415, "detergent"),
                   ("IR", 12.5, 6902, 1433, "rinse"), ("HNO3-1", 18.2, 6966, 469, "detergent"),
                   ("IR", 16.8, 6996, 1457, "rinse"), ("NaOH-2", 18.2, 6892, 456, "detergent"),
                   ("IR", 12.5, 6816, 1415, "rinse"), ("HNO3-2", 18.2, 6873, 449, "detergent"),
                   ("FR", 14.0, 6977, 1734, "rinse")],
       "revised": [("flushing-first rinse", 13.6, (1990 + 5845) / 2, 542, "rinse"), ("NaOH-1", 16.1, 6344, 423, "detergent"),
                   ("IR", 7.0, 6984, 815, "rinse"), ("HNO3-1", 7.2, 7002, 469, "detergent"),
                   ("IR", 7.0, 7002, 816, "rinse"), ("HNO3-2", 7.2, 6995, 466, "detergent"),
                   ("FR", 7.8, 6984, 907, "rinse")]}
wb = {}
for seq, ph in alv.items():
    for name, dur, q, eff, kind in ph:
        circ = q * dur / 60.0
        rows.append(dict(segment="D water balance, industrial CIP", source="Alvarez et al. (2010)",
                         condition=f"{seq} sequence, {name}", simulator_rate="once-through (Q x t)",
                         quantity="volume (L): once-through vs effluent", predicted=circ, observed=eff, observed_basis="quoted"))
    df = pd.DataFrame(ph, columns=["phase", "min", "L_h", "effluent_L", "kind"])
    df["circ"] = df.L_h * df["min"] / 60.0
    wb[seq] = {k: dict(once_through_L=float(g.circ.sum()), effluent_L=float(g.effluent_L.sum()),
                       ratio=float(g.circ.sum() / g.effluent_L.sum())) for k, g in df.groupby("kind")}
    wb[seq]["total"] = dict(once_through_L=float(df.circ.sum()), effluent_L=float(df.effluent_L.sum()),
                            ratio=float(df.circ.sum() / df.effluent_L.sum()))

res = pd.DataFrame(rows)
res["ratio_pred_obs"] = res.predicted / res.observed

# ---------------------------------------------------------------- E  invariance under a common error in the rate scale
# Every rate enters the simulator only through k_i * t_i, so multiplying all rates by c and all phase durations by 1/c
# leaves CS, Rres and COD unchanged and divides water, energy and carbon by c (caps on CS, Rres and COD unchanged).
# Checked numerically on the candidate envelope with the U3 draws of the candidate audit (common random numbers).
from cip_closed_form import simulate  # noqa: E402
import run_robustness_audit as rra   # noqa: E402

z = np.load(os.path.join(ROOT, "results", "candidate_q10.npz"))
Xc = z["X"]
C_SCALE = 30.0
M_chk = 1000
W_RAW = {"balanced_default": [0.20, 0.20, 0.20, 0.20, 0.10], "cod_discharge_limit": [0.15, 0.10, 0.40, 0.10, 0.15],
         "hygiene_priority": [0.10, 0.10, 0.15, 0.10, 0.55]}


def nominal(f):
    """Nominal outputs (s0 = 0.5) with all rates x f and all durations / f."""
    return simulate(Xc[:, 0], Xc[:, 1], Xc[:, 2] / f, Xc[:, 3] / f, Xc[:, 4] / f, Xc[:, 5] / f, Xc[:, 6], Xc[:, 7],
                    Xc[:, 8], Xc[:, 9], k_cal=P["k_cal"] * f)


def caps(Y):
    return {"balanced_default": Y["cleaning_score"] >= 95,
            "cod_discharge_limit": (Y["cleaning_score"] >= 95) & (Y["COD_mgL"] <= 700),
            "hygiene_priority": (Y["cleaning_score"] >= 98) & (Y["hygienic_risk"] <= 0.1)}


def weighted(Y, mask, w):
    idx = np.where(mask)[0]
    if len(idx) == 0:
        return -1

    def nz(v):
        v = v[idx]
        s = v.max() - v.min()
        return (v - v.min()) / (s if s > 0 else 1)
    w = np.asarray(w, float) / np.sum(w)
    sc = (w[0] * nz(Y["water_L"]) + w[1] * nz(Y["total_energy_kWh"]) + w[2] * nz(Y["COD_mgL"])
          + w[3] * nz(Y["CO2eq_kg"]) + w[4] * (1 - nz(Y["cleaning_score"])))
    return int(idx[np.argmin(sc)])


def audit(f, lev):
    d = rra.draws(lev, M_chk, np.random.default_rng(rra.SEED + 1))
    dd = {k: v[None, :] for k, v in d.items()}
    q, r = np.empty(len(Xc)), np.empty(len(Xc))
    for a in range(0, len(Xc), 500):
        Xb = Xc[a:a + 500]
        T, Q, Cn = rra.realised(Xb[:, [0]], Xb[:, [1]], Xb[:, [6]], dd)
        y = simulate(T, Q, Xb[:, [2]] / f, Xb[:, [3]] / f, Xb[:, [4]] / f, Xb[:, [5]] / f, Cn, dd["s0"], Xb[:, [8]],
                     Xb[:, [9]], T_in=dd["T_in"], k_cal=dd["k_cal"] * f, alpha_T=dd["alpha_T"], beta_Q=dd["beta_Q"],
                     gamma=dd["gamma"])
        q[a:a + 500] = np.quantile(y["cleaning_score"], 0.10, axis=1)
        r[a:a + 500] = np.quantile(y["hygienic_risk"], 0.90, axis=1)
    return q, r


Y1, Y2 = nominal(1.0), nominal(C_SCALE)
inv = dict(scale_factor=C_SCALE, n_candidates=len(Xc), M=M_chk,
           nominal_max_abs_diff={k: float(np.max(np.abs(Y1[k] - Y2[k]))) for k in ("cleaning_score", "hygienic_risk", "COD_mgL")},
           resource_ratio={k: [float(np.min(Y1[k] / Y2[k])), float(np.max(Y1[k] / Y2[k]))]
                           for k in ("water_L", "total_energy_kWh", "CO2eq_kg")},
           EEPI_not_invariant_ratio=[float(np.min(Y1["EHPI"] / Y2["EHPI"])), float(np.max(Y1["EHPI"] / Y2["EHPI"]))],
           caps_identical=bool(all(np.array_equal(caps(Y1)[p], caps(Y2)[p]) for p in W_RAW)))
sel_diff = 0
for lev in ("U0", "U3"):
    (q1, r1), (q2, r2) = audit(1.0, lev), audit(C_SCALE, lev)
    inv[f"{lev}_max_abs_diff_q10_CS"] = float(np.max(np.abs(q1 - q2)))
    inv[f"{lev}_max_abs_diff_q90_Rres"] = float(np.max(np.abs(r1 - r2)))
    inv[f"{lev}_verdict_mismatches"] = int(np.sum((q1 >= 95) != (q2 >= 95)))
    for prof, w in W_RAW.items():
        for m1, m2 in ((np.ones(len(Xc), bool), np.ones(len(Xc), bool)), (q1 >= 95, q2 >= 95)):
            sel_diff += int(weighted(Y1, caps(Y1)[prof] & m1, w) != weighted(Y2, caps(Y2)[prof] & m2, w))
inv["selections_compared"] = 2 * len(W_RAW) * 2
inv["selections_different"] = sel_diff
inv["verdicts_identical"] = bool(inv["U0_verdict_mismatches"] == 0 and inv["U3_verdict_mismatches"] == 0)
inv["max_abs_diff_q10_CS"] = max(inv["U0_max_abs_diff_q10_CS"], inv["U3_max_abs_diff_q10_CS"])

# ---------------------------------------------------------------- F  rate-scale factor implied by the data
g50 = res[(res.segment.str.startswith("C")) & (res.simulator_rate == "alk") & (res.T_eval == 50.0)]
g70 = res[(res.segment.str.startswith("C")) & (res.simulator_rate == "alk") & (res.T_eval == 70.0)]
pc = res[(res.segment.str.startswith("B")) & (res.simulator_rate == "alk")]
# test bed: the observed residual after 30 min is an upper bound, so the factor is a lower bound
c_pant = [float(np.log(100.0 / 0.21) / np.log(100.0 / p)) for p in pc.predicted]
c_pant += [float(np.log(100.0 / 0.1) / np.log(100.0 / p)) for p in pc.predicted]
scale = dict(gillham_tubes_50C=[float(g50.ratio_pred_obs.min()), float(g50.ratio_pred_obs.max())],
             gillham_tubes_70C=[float(g70.ratio_pred_obs.min()), float(g70.ratio_pred_obs.max())],
             pant_test_bed_lower_bound=[min(c_pant), max(c_pant)])
res.to_csv(os.path.join(OUT, "E49_full_cycle_segment_tests.csv"), index=False, float_format="%.4g")


def rng(mask, col="ratio_pred_obs"):
    x = res.loc[mask, col].dropna()
    return [float(x.min()), float(x.max())]


S = dict(
    simulator="closed-form pipe-circuit simulator with the assumed parameters (no refit)",
    A_pre_rinse=dict(pred_residual_pct_20s_pre=rng((res.segment.str.startswith("A")) & (res.simulator_rate == "pre")
                                                     & res.condition.str.endswith("20 s"), "predicted"),
                     pred_residual_pct_60s_pre=rng((res.segment.str.startswith("A")) & (res.simulator_rate == "pre")
                                                     & res.condition.str.endswith("60 s"), "predicted"),
                     obs_residual_pct_20s_22C=[9.3, 26.9], obs_residual_pct_20s_all=[5.1, 26.9]),
    B_pilot=dict(water_pred_residual_rinse_rate=rng((res.segment.str.startswith("B")) & (res.simulator_rate == "rinse"), "predicted"),
                 water_pred_residual_pre_rate=rng((res.segment.str.startswith("B")) & (res.simulator_rate == "pre"), "predicted"),
                 water_obs=[11.14, 26.88],
                 caustic_pred_residual=rng((res.segment.str.startswith("B")) & (res.simulator_rate == "alk"), "predicted"),
                 caustic_obs=[0.1, 0.21]),
    C_tubes={f"{who}_ratio_t_{Td:g}C_{band}": rng((res.segment.str.startswith("C")) & sel & (res.T_eval == Td) & vm)
             for who, sel in (("simulator", res.simulator_rate == "alk"),
                              ("uniform_law", res.simulator_rate.str.startswith("calibrated")))
             for Td in (50.0, 70.0)
             for band, vm in (("v_15_47", res.v_cm_s < 50), ("v_92", res.v_cm_s > 50))},
    D_water_balance=wb, E_rate_scale_invariance=inv, F_alkaline_rate_factor_implied=scale)
json.dump(S, open(os.path.join(OUT, "E49_summary.json"), "w"), indent=2)
with pd.option_context("display.width", 250, "display.max_colwidth", 70):
    print(res.round(3).to_string(index=False))
print(json.dumps(S, indent=2))
