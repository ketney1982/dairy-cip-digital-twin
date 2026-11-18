# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""E46 - The audit compared with a stricter nominal cleaning floor (no new simulation).

Can a higher nominal floor, CS_nominal >= tau, replace the audit under U3?  For both cases the candidates are
classified by the nominal rule for tau = 95 ... 100% and by the smallest tau that admits no candidate failing the U3
audit; for each rule the script counts the candidates admitted, those admitted although they fail under U3 and those
rejected although they pass, and reports the least-burden recipe that the rule admits and its own U3 verdict.
As in E29, the reference is the U3 audit itself (point estimates of q0.10(CS)), not cleaning observed on a plant.

  calibrated case : the 30,000 candidates of E17 (uniform-removal law M0 and first-order law M1); least burden =
                    smallest volume of solution (the minimum-volume selection of Table 4)
  pipe circuit    : the 30,000-candidate policy envelope (results/candidate_q10.npz, simulator values, s0 = 0.5);
                    least burden = smallest total energy, and the balanced-default weighted selection with and
                    without the CODorg weight (weights of src/run_robustness_audit.py)

Inputs : ../outputs/E17_candidates.csv (run e17 first), ../../results/candidate_q10.npz
Outputs: ../outputs/E46_nominal_threshold_benchmark.csv, ../outputs/E46_summary.json
"""
import json
import os

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "outputs")
RES = os.path.join(HERE, "..", "..", "results")
FLOOR = 95.0
TAUS = (95.0, 96.0, 97.0, 98.0, 99.0, 99.5, 99.9, 100.0)


def smallest_safe_tau(cs, ref):
    """Smallest threshold on the nominal CS that admits no candidate failing the reference (None if none exists)."""
    fail = cs[(cs >= FLOOR) & ~ref]
    if len(fail) == 0:
        return FLOOR
    above = np.unique(cs[cs > fail.max()])
    return float(above[0]) if len(above) else None


def weighted(Y, mask, w):
    """Lowest weighted sum of min-max normalised objectives (as in src/run_robustness_audit.py)."""
    idx = np.where(mask)[0]
    if len(idx) == 0:
        return None

    def nz(v):
        v = v[idx]
        s = v.max() - v.min()
        return (v - v.min()) / (s if s > 0 else 1)

    w = np.asarray(w, float) / np.sum(w)
    sc = (w[0] * nz(Y["water_L"]) + w[1] * nz(Y["total_energy_kWh"]) + w[2] * nz(Y["COD_mgL"])
          + w[3] * nz(Y["CO2eq_kg"]) + w[4] * (1 - nz(Y["cleaning_score"])))
    return idx[np.argmin(sc)]


def rules(cs, ref):
    out = [(f"nominal CS >= {t:g}%", t, cs >= t) for t in TAUS]
    ts = smallest_safe_tau(cs, ref)
    if ts is not None:
        out.append((f"nominal CS >= {ts:.4g}% (smallest without false admission)", ts, cs >= ts))
    out.append(("audit, U3 (reference)", None, (cs >= FLOOR) & ref))
    return out, ts


def calibrated():
    res = pd.read_csv(os.path.join(OUT, "E17_candidates.csv"))
    rows, summ = [], {}
    for model, law in (("M0", "uniform removal"), ("M1", "first order")):
        cs = res[f"CS_nom_{model}"].to_numpy()
        q3 = res[f"q10_U3_{model}"].to_numpy()
        ref = (cs >= FLOOR) & (q3 >= FLOOR)
        rl, ts = rules(cs, ref)
        fail_at_100 = int(((cs >= 100.0) & ~ref).sum())
        for name, tau, adm in rl:
            j = res.V_L.where(adm).idxmin() if adm.any() else None
            r = res.loc[j] if j is not None else None
            rows.append(dict(case="calibrated channel", law=law, rule=name, tau=tau, admitted=int(adm.sum()),
                             admitted_but_fail_U3=int((adm & ~ref).sum()), rejected_but_pass_U3=int((~adm & ref).sum()),
                             least_burden_recipe=None if r is None else
                             f"{r.T_C:.1f} C, {r.v_cm_s:.2f} cm/s, {r.t_min:.1f} min",
                             least_burden_value=None if r is None else float(r.V_L), least_burden_unit="L",
                             least_burden_q10_U3=None if r is None else float(r[f"q10_U3_{model}"]),
                             least_burden_passes_U3=None if r is None else bool(ref[j])))
        summ[law] = dict(n_candidates=len(cs), n_fail_U3_with_nominal_CS_100=fail_at_100, smallest_safe_tau=ts,
                         n_nominal_CS_100=int((cs >= 100.0).sum()))
    return rows, summ


def pipe_circuit():
    z = np.load(os.path.join(RES, "candidate_q10.npz"))
    Y = {k: z[k] for k in ["water_L", "total_energy_kWh", "COD_mgL", "CO2eq_kg", "cleaning_score"]}
    cs, q3 = Y["cleaning_score"], z["U3"]
    ref = (cs >= FLOOR) & (q3 >= FLOOR)
    rl, ts = rules(cs, ref)
    rows = []
    w_bd = [0.20, 0.20, 0.20, 0.20, 0.10]
    w_bd0 = [0.20, 0.20, 0.00, 0.20, 0.10]
    for name, tau, adm in rl:
        j = int(np.where(adm)[0][np.argmin(Y["total_energy_kWh"][adm])]) if adm.any() else None
        row = dict(case="pipe circuit (assumed parameters)", law="first order", rule=name, tau=tau,
                   admitted=int(adm.sum()), admitted_but_fail_U3=int((adm & ~ref).sum()),
                   rejected_but_pass_U3=int((~adm & ref).sum()),
                   least_burden_recipe=None if j is None else f"{Y['water_L'][j]:.0f} L, CS {cs[j]:.2f}%",
                   least_burden_value=None if j is None else float(Y["total_energy_kWh"][j]), least_burden_unit="kWh",
                   least_burden_q10_U3=None if j is None else float(q3[j]),
                   least_burden_passes_U3=None if j is None else bool(ref[j]))
        for tag, w in (("bd", w_bd), ("bd_noCOD", w_bd0)):
            k = weighted(Y, adm, w)
            row[f"{tag}_water_L"] = None if k is None else float(Y["water_L"][k])
            row[f"{tag}_energy_kWh"] = None if k is None else float(Y["total_energy_kWh"][k])
            row[f"{tag}_CS"] = None if k is None else float(cs[k])
            row[f"{tag}_q10_U3"] = None if k is None else float(q3[k])
            row[f"{tag}_passes_U3"] = None if k is None else bool(ref[k])
        rows.append(row)
    return rows, dict(n_feasible=int((cs >= FLOOR).sum()), smallest_safe_tau=ts,
                      max_nominal_CS_of_U3_failures=float(cs[(cs >= FLOOR) & ~ref].max()),
                      min_nominal_CS_of_U3_passes=float(cs[ref].min()))


def main():
    r1, s1 = calibrated()
    r2, s2 = pipe_circuit()
    df = pd.DataFrame(r1 + r2)
    df.to_csv(os.path.join(OUT, "E46_nominal_threshold_benchmark.csv"), index=False, float_format="%.6g")
    json.dump(dict(calibrated=s1, pipe_circuit=s2), open(os.path.join(OUT, "E46_summary.json"), "w"), indent=2)
    with pd.option_context("display.width", 250, "display.max_columns", 30, "display.max_colwidth", 60):
        print(df.to_string(index=False))
    print(json.dumps(dict(calibrated=s1, pipe_circuit=s2), indent=2))


if __name__ == "__main__":
    main()
