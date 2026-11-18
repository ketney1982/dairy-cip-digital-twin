# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""E40 - Two checks added in the consolidation of the second revision (no new simulation).

A. Illustrative pipe-circuit case: is the organic-load proxy CODorg needed?  At s0 = 0.5, CODorg = kCOD (CS/100 - 0.5)
   is an exact increasing function of CS, so that minimising CODorg and maximising CS oppose each other exactly.
   The non-dominated set of the 30,000-candidate policy envelope (simulator values, results/candidate_q10.npz) is
   determined with the five objectives of Supplementary Eq. (S5), without CODorg (water, energy, carbon, CS) and with
   the three burdens only (CS >= 95% as a constraint), and the audit verdicts under U0 and U3 (stored q0.10 values,
   M = 1,000) are counted for each set.  The balanced-default and cleaning-priority selections (nominal and
   audit-then-select) are repeated with the CODorg weight set to zero, and the 76 recipes of the gamultiobj front
   (results/pareto_front_audit.csv) are re-sorted without CODorg.
B. Calibrated case, retrospective check (cross-validated, E26_C): sensitivity of the verdicts to the estimate of the
   terminal cleaning score.  For wash times within the record: the observed score and the share of verdicts that a
   digitisation error of 2 standard deviations could reverse.  For wash times after the last measured point: last
   point, last two points, mean of the last three points, last point minus 2 standard deviations of the digitisation
   error, and the first crossing of the floor by linear interpolation.

Outputs (../outputs): E40_A_fronts_without_CODorg.csv, E40_A_selection_without_CODorg.csv,
                      E40_A_gamultiobj_front.csv, E40_B_terminal_score_sensitivity.csv, E40_summary.json
"""
import json
import os

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "outputs")
RES = os.path.join(HERE, "..", "..", "results")
FLOOR, H_REF, K_COD = 95.0, 3.0, 45.0


# ------------------------------------------------------------------------------------------------ helpers
def nondominated(F):
    """Boolean mask of the non-dominated rows of F (all objectives minimised)."""
    n = len(F)
    keep = np.ones(n, bool)
    for a in range(0, n, 256):
        Fi = F[a:a + 256][:, None, :]
        le = (F[None, :, :] <= Fi).all(axis=2)
        lt = (F[None, :, :] < Fi).any(axis=2)
        keep[a:a + 256] = ~(le & lt).any(axis=1)
    return keep


def select(Y, mask, w):
    """Lowest weighted sum of min-max normalised objectives (as in src/run_robustness_audit.py)."""
    idx = np.where(mask)[0]
    if len(idx) == 0:
        return None

    def nz(v):
        v = v[idx]
        s = v.max() - v.min()
        return (v - v.min()) / (s if s > 0 else 1)

    w = np.asarray(w, float)
    w = w / w.sum()
    sc = (w[0] * nz(Y["water_L"]) + w[1] * nz(Y["total_energy_kWh"]) + w[2] * nz(Y["COD_mgL"])
          + w[3] * nz(Y["CO2eq_kg"]) + w[4] * (1 - nz(Y["cleaning_score"])))
    return idx[np.argmin(sc)]


# ------------------------------------------------------------------------------------------------ part A
def part_A():
    z = np.load(os.path.join(RES, "candidate_q10.npz"))
    Y = {k: z[k] for k in ["water_L", "total_energy_kWh", "COD_mgL", "CO2eq_kg", "cleaning_score", "hygienic_risk"]}
    q0, q3 = z["U0"], z["U3"]
    cs = Y["cleaning_score"]
    feas = cs >= FLOOR
    # CODorg is an exact linear function of CS at s0 = 0.5
    lin = np.polyfit(cs, Y["COD_mgL"], 1)
    resid = np.abs(Y["COD_mgL"] - np.polyval(lin, cs)).max()

    sets = {
        "five objectives (water, energy, CODorg, carbon, -CS)": ["water_L", "total_energy_kWh", "COD_mgL", "CO2eq_kg", "-CS"],
        "four objectives (water, energy, carbon, -CS)": ["water_L", "total_energy_kWh", "CO2eq_kg", "-CS"],
        "three burdens (water, energy, carbon); CS >= 95% as constraint": ["water_L", "total_energy_kWh", "CO2eq_kg"],
    }
    idx = np.where(feas)[0]
    rows = []
    for name, cols in sets.items():
        F = np.column_stack([-cs[idx] if c == "-CS" else Y[c][idx] for c in cols])
        nd = idx[nondominated(F)]
        rows.append(dict(objective_set=name, n_feasible=int(feas.sum()), n_nondominated=len(nd),
                         share_of_feasible=len(nd) / feas.sum(),
                         admitted_U0=int((q0[nd] >= FLOOR).sum()), admitted_U3=int((q3[nd] >= FLOOR).sum()),
                         share_admitted_U3=float((q3[nd] >= FLOOR).mean()),
                         q10_U3_min=float(q3[nd].min()), q10_U3_median=float(np.median(q3[nd])),
                         q10_U3_max=float(q3[nd].max()),
                         CS_nominal_min=float(cs[nd].min()), CS_nominal_median=float(np.median(cs[nd])), CS_nominal_max=float(cs[nd].max()),
                         water_L_min=float(Y["water_L"][nd].min()), energy_kWh_min=float(Y["total_energy_kWh"][nd].min())))
    fronts = pd.DataFrame(rows)
    fronts.to_csv(os.path.join(OUT, "E40_A_fronts_without_CODorg.csv"), index=False, float_format="%.6g")

    # policy selections with and without the CODorg weight (weights of src/run_robustness_audit.py)
    caps = {"balanced_default": feas, "hygiene_priority": (cs >= 98) & (Y["hygienic_risk"] <= 0.1)}
    w_raw = {"balanced_default": [0.20, 0.20, 0.20, 0.20, 0.10], "hygiene_priority": [0.10, 0.10, 0.15, 0.10, 0.55]}
    srows = []
    for prof, m in caps.items():
        for wname in ("with CODorg weight", "CODorg weight = 0"):
            w = list(w_raw[prof])
            if wname != "with CODorg weight":
                w[2] = 0.0
            for scr, mask in (("nominal", m), ("audit-then-select U0", m & (q0 >= FLOOR)),
                              ("audit-then-select U3", m & (q3 >= FLOOR))):
                j = select(Y, mask, w)
                srows.append(dict(profile=prof, weights=wname, screening=scr, n=int(mask.sum()), candidate=int(j),
                                  water_L=Y["water_L"][j], energy_kWh=Y["total_energy_kWh"][j], CO2eq_kg=Y["CO2eq_kg"][j],
                                  CS_nominal=cs[j], q10_U0=q0[j], q10_U3=q3[j],
                                  admitted_U3=bool(q3[j] >= FLOOR)))
    sel = pd.DataFrame(srows)
    for (prof, wname), g in sel.groupby(["profile", "weights"]):
        nom = g[g.screening == "nominal"].iloc[0]
        for k in g.index:
            sel.loc[k, "water_over_nominal"] = sel.loc[k, "water_L"] / nom.water_L
            sel.loc[k, "energy_over_nominal"] = sel.loc[k, "energy_kWh"] / nom.energy_kWh
    sel.to_csv(os.path.join(OUT, "E40_A_selection_without_CODorg.csv"), index=False, float_format="%.6g")

    # gamultiobj front (76 recipes, simulator values at s0 = 0.5)
    pf = pd.read_csv(os.path.join(RES, "pareto_front_audit.csv"))
    pf["COD_from_CS"] = K_COD * (pf["simulator_cleaning_score"] / 100 - 0.5)
    ok = pf["simulator_cleaning_score"] >= FLOOR
    F5 = pf[["simulator_water_L", "simulator_total_energy_kWh", "COD_from_CS", "simulator_CO2eq_kg"]].to_numpy()
    F5 = np.column_stack([F5, -pf["simulator_cleaning_score"].to_numpy()])
    F4 = F5[:, [0, 1, 3, 4]]
    pf["nondominated_5obj_within_front"] = False
    pf["nondominated_4obj_within_front"] = False
    pf.loc[ok, "nondominated_5obj_within_front"] = nondominated(F5[ok.to_numpy()])
    pf.loc[ok, "nondominated_4obj_within_front"] = nondominated(F4[ok.to_numpy()])
    pf.to_csv(os.path.join(OUT, "E40_A_gamultiobj_front.csv"), index=False, float_format="%.6g")
    g4 = pf[pf.nondominated_4obj_within_front]
    gam = dict(n_front=len(pf), n_feasible=int(ok.sum()),
               n_nondominated_5obj=int(pf.nondominated_5obj_within_front.sum()),
               n_nondominated_4obj=len(g4), admitted_U0_4obj=int(g4.admitted_U0.sum()),
               admitted_U3_4obj=int(g4.admitted_U3.sum()),
               admitted_U0_all_feasible=int(pf[ok].admitted_U0.sum()), admitted_U3_all_feasible=int(pf[ok].admitted_U3.sum()))
    return dict(CODorg_linear_in_CS=dict(slope=lin[0], intercept=lin[1], max_abs_residual=resid)), fronts, sel, gam


# ------------------------------------------------------------------------------------------------ part B
def part_B():
    cv = pd.read_csv(os.path.join(OUT, "E26_C_retrospective_status.csv"))
    per = pd.read_csv(os.path.join(OUT, "E16_per_curve_fits.csv")).set_index("curve")
    obs = pd.read_csv(os.path.join(OUT, "E16_observed_vs_predicted.csv"))
    obs = obs[obs.model == "M0"]
    dg = json.load(open(os.path.join(OUT, "E26_B_digitisation_summary.json")))["settings"]
    s_y = float(np.hypot(dg["s_y_rand"], dg["s_y_sys"]))          # digitisation error of y = S/S0 (1 sd)
    rows = []
    for _, r in cv.iterrows():
        g = obs[obs.curve == r.curve].sort_values("t_min")
        h0 = per.loc[r.curve, "h0_mm"] if "h0_mm" in per.columns and pd.notna(per.loc[r.curve, "h0_mm"]) else H_REF
        cs = lambda y: 100.0 * (1.0 - np.asarray(y) * h0 / H_REF)
        s_cs = 100.0 * s_y * h0 / H_REF                            # digitisation error of CS (1 sd)
        row = dict(curve=r.curve, wash_time_rule=r.wash_time_rule, wash_time_min=r.wash_time_min,
                   t_end_obs_min=r.t_end_obs_min, within_record=bool(r.within_record), sd_CS_digitisation=s_cs)
        if r.within_record:
            row.update(observed_CS=r.observed_CS, observed_pass=bool(r.observed_pass),
                       verdict_reversible_2sd=bool(abs(r.observed_CS - FLOOR) <= 2 * s_cs))
        else:
            ys = cs(g.y_obs.to_numpy())
            row.update(CS_last=ys[-1], pass_last=bool(ys[-1] >= FLOOR),
                       pass_last_two=bool((ys[-2:] >= FLOOR).all()),
                       CS_mean_last3=float(ys[-3:].mean()), pass_mean_last3=bool(ys[-3:].mean() >= FLOOR),
                       pass_last_minus_2sd=bool(ys[-1] - 2 * s_cs >= FLOOR),
                       t_floor_crossing_min=r.t_floor_crossing_obs_min,
                       pass_crossing_before_wash_time=bool(r.floor_crossed_by_wash_time))
        rows.append(row)
    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(OUT, "E40_B_terminal_score_sensitivity.csv"), index=False, float_format="%.5g")
    summ = {}
    for rule, g in df.groupby("wash_time_rule"):
        w, a = g[g.within_record], g[~g.within_record]
        summ[rule] = dict(n_curves=len(g), within_record=len(w), observed_below_floor=int((~w.observed_pass.astype(bool)).sum()),
                          within_record_reversible_2sd=int(w.verdict_reversible_2sd.astype(bool).sum()),
                          after_record=len(a),
                          pass_last_point=int(a.pass_last.astype(bool).sum()),
                          pass_last_two_points=int(a.pass_last_two.astype(bool).sum()),
                          pass_mean_last3=int(a.pass_mean_last3.astype(bool).sum()),
                          pass_last_minus_2sd=int(a.pass_last_minus_2sd.astype(bool).sum()),
                          pass_crossing_before_wash_time=int(a.pass_crossing_before_wash_time.astype(bool).sum()),
                          min_CS_last=float(a.CS_last.min()) if len(a) else None)
    return dict(sd_y_digitisation=s_y, by_rule=summ), df


def part_A_extra(sel):
    """Robustness of the CODorg finding (added after the independent review of 18 November 2026):
    (i) audit verdict by nominal CS band over the whole envelope; (ii) sensitivity of the balanced-default selection to
    the CODorg and CS weights; (iii) dominance of the audit-then-select recipe chosen with the CODorg weight and the same
    selection with the min-max ranges fixed on the nominally feasible set; (iv) correlation of carbon and energy."""
    z = np.load(os.path.join(RES, "candidate_q10.npz"))
    Y = {k: z[k] for k in ["water_L", "total_energy_kWh", "COD_mgL", "CO2eq_kg", "cleaning_score"]}
    cs, q3 = Y["cleaning_score"], z["U3"]
    feas = cs >= FLOOR
    bands = dict(n_CS_below_98=int((feas & (cs < 98)).sum()), pass_U3_CS_below_98=int((feas & (cs < 98) & (q3 >= FLOOR)).sum()),
                 n_CS_at_least_98p9=int((cs >= 98.9).sum()), pass_U3_CS_at_least_98p9=int(((cs >= 98.9) & (q3 >= FLOOR)).sum()))
    sweep = []
    for w_cod, w_cs in ((0.0, 0.10), (0.05, 0.10), (0.0, 0.05), (0.10, 0.10), (0.20, 0.10)):
        j = select(Y, feas, [0.20, 0.20, w_cod, 0.20, w_cs])
        sweep.append(dict(w_COD=w_cod, w_CS=w_cs, candidate=int(j), CS=float(cs[j]), q10_U3=float(q3[j]),
                          admitted_U3=bool(q3[j] >= FLOOR)))
    ats = sel[(sel.profile == "balanced_default") & (sel.weights == "with CODorg weight")
              & (sel.screening == "audit-then-select U3")].iloc[0]
    j = int(ats.candidate)
    adm = np.where(feas & (q3 >= FLOOR))[0]
    dom = adm[(Y["water_L"][adm] <= Y["water_L"][j]) & (Y["total_energy_kWh"][adm] <= Y["total_energy_kWh"][j])
              & (Y["CO2eq_kg"][adm] <= Y["CO2eq_kg"][j]) & (cs[adm] >= cs[j]) & (adm != j)]

    def select_fixed(mask, w):
        idx = np.where(mask)[0]

        def nz(v):
            lo, hi = v[feas].min(), v[feas].max()
            return (v[idx] - lo) / (hi - lo)
        w = np.asarray(w, float) / np.sum(w)
        sc = (w[0] * nz(Y["water_L"]) + w[1] * nz(Y["total_energy_kWh"]) + w[2] * nz(Y["COD_mgL"])
              + w[3] * nz(Y["CO2eq_kg"]) + w[4] * (1 - nz(cs)))
        return int(idx[np.argmin(sc)])
    fixed = {"ATS_U3_with_CODorg": select_fixed(feas & (q3 >= FLOOR), [0.2, 0.2, 0.2, 0.2, 0.1]),
             "ATS_U3_CODorg_0": select_fixed(feas & (q3 >= FLOOR), [0.2, 0.2, 0.0, 0.2, 0.1]),
             "nominal_CODorg_0": select_fixed(feas, [0.2, 0.2, 0.0, 0.2, 0.1])}
    return dict(CS_bands=bands, weight_sweep=sweep,
                ATS_U3_with_CODorg=dict(candidate=j, n_admitted_dominating=int(len(dom)),
                                        example_dominating=int(dom[np.argmin(Y["water_L"][dom])]) if len(dom) else None),
                selection_ranges_fixed_on_feasible_set=fixed,
                r_CO2_energy_feasible=float(np.corrcoef(Y["CO2eq_kg"][feas], Y["total_energy_kWh"][feas])[0, 1]))


def confirm_selected(sel):
    """Recipes selected in part A re-audited with an independent sample (M = 10,000, seed of the re-check in
    src/run_conservative_selection.py) under U0-U3; distribution-free 95% interval of q0.10(CS)."""
    import sys
    sys.path.insert(0, os.path.join(HERE, "..", "..", "src"))
    from cip_closed_form import LB, UB, matlab_rand                     # noqa: E402
    from run_robustness_audit import draws, SEED                        # noqa: E402
    from run_conservative_selection import q10_with_interval, SEED_RECHECK  # noqa: E402
    Xc = LB + matlab_rand(42, 30000, 10) * (UB - LB)
    Xc[:, 7] = 0.5
    js = sorted(set(sel.candidate))
    rows = []
    for lev in ("U0", "U1", "U2", "U3"):
        d = draws(lev, 10000, np.random.default_rng(SEED_RECHECK))
        q, ql, qh = q10_with_interval(Xc[js], d, chunk=len(js))
        rows += [dict(candidate=j, uncertainty=lev, q10=q[i], q10_lower=ql[i], q10_upper=qh[i]) for i, j in enumerate(js)]
    c = pd.DataFrame(rows).pivot(index="candidate", columns="uncertainty")
    c.columns = [f"{a}_{b}_M10000" for a, b in c.columns]
    out = sel.merge(c, left_on="candidate", right_index=True)
    out["confirmed_U3"] = out["q10_lower_U3_M10000"] >= FLOOR
    out.to_csv(os.path.join(OUT, "E40_A_selection_without_CODorg.csv"), index=False, float_format="%.6g")
    return out


if __name__ == "__main__":
    lin, fronts, sel, gam = part_A()
    sel = confirm_selected(sel)
    sB, dfB = part_B()
    summary = dict(A=dict(lin, gamultiobj_front=gam, robustness_of_finding=part_A_extra(sel)), B=sB)
    print(sel[["profile", "weights", "screening", "q10_U3", "q10_U3_M10000", "q10_lower_U3_M10000", "q10_U0_M10000",
               "confirmed_U3"]].round(2).to_string())
    json.dump(summary, open(os.path.join(OUT, "E40_summary.json"), "w"), indent=1, default=float)
    pd.set_option("display.width", 250)
    print(fronts.round(3).to_string())
    print(sel[["profile", "weights", "screening", "n", "water_L", "energy_kWh", "CS_nominal", "q10_U3", "admitted_U3",
               "water_over_nominal", "energy_over_nominal"]].round(3).to_string())
    print(json.dumps(summary, indent=1, default=float))
