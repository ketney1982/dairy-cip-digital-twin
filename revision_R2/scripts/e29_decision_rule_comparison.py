# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""E29 - Calibrated case: the Monte Carlo audit compared with deterministic admission rules.

The 30,000 candidate recipes of E17 (same candidates, same audit results) are classified by five rules:

  nominal          CS >= floor at the nominal deposit thickness (2.44 mm)
  maximum load     CS >= floor at the maximum deposit thickness (3 mm)
  fixed margin f   wash time >= f x the shortest wash time that meets the floor at the nominal thickness
                   and the candidate's own temperature and velocity (f = 1.2, 1.5, 2.0 and the smallest f
                   that admits no candidate failing the U3 audit)
  audit, U0        q0.10(CS) >= floor under variation of the deposit thickness alone
  audit, U3        q0.10(CS) >= floor under the full uncertainty set (reference)

For every rule the script counts the candidates admitted, those admitted although they fail the U3 audit
and those rejected although they pass it. Point estimates of q0.10(CS) are used, as for the counts 21,318
and 18,475 of the manuscript (Table 4, note). No new simulation is run: the script reads the audit results
written by e17_calibrated_case_audit.py.

Input:  ../outputs/E17_candidates.csv (written by e17; 3.5 MB, not stored in the repository - run e17 first),
        ../outputs/E16_calibrated_rate_law.json
Output: ../outputs/E29_decision_rule_comparison.csv
"""
import os
import json
import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "outputs")
cal = json.load(open(os.path.join(OUT, "E16_calibrated_rate_law.json")))
H_REF, H_NOM, FLOOR = 3.0, 2.44, 95.0
H_FLOOR = H_REF * (1.0 - FLOOR / 100.0)          # residual thickness at the floor, 0.15 mm
FACTORS = (1.2, 1.5, 2.0)


def rate(model, T, v):
    c = cal[model]
    return c["ref"] * np.exp(c["alpha_per_degC"] * (T - cal["T_ref_C"])) * (v / cal["v_ref_cm_s"]) ** c["beta"]


def t_nominal(model, T, v):
    """Shortest wash time meeting the floor at the nominal thickness (closed form)."""
    r = rate(model, T, v)
    return (H_NOM - H_FLOOR) / r if model == "M0" else np.log(H_NOM / H_FLOOR) / r


def main():
    res = pd.read_csv(os.path.join(OUT, "E17_candidates.csv"))
    T, v, t = res.T_C.to_numpy(), res.v_cm_s.to_numpy(), res.t_min.to_numpy()
    rows = []
    for model, law in (("M0", "uniform removal"), ("M1", "first order")):
        nom = (res[f"CS_nom_{model}"] >= FLOOR).to_numpy()
        ref = nom & (res[f"q10_U3_{model}"] >= FLOOR).to_numpy()
        margin = t / t_nominal(model, T, v)                       # realised wash time / nominally sufficient time
        f_safe = float(np.ceil(margin[nom & ~ref].max() * 100.0) / 100.0) if (nom & ~ref).any() else 1.0
        rules = [("nominal", nom),
                 ("maximum load (3 mm)", nom & (res[f"CS_h0_3p0_{model}"] >= FLOOR).to_numpy())]
        rules += [(f"fixed margin {f:.2f}", margin >= f) for f in FACTORS]
        rules += [(f"fixed margin {f_safe:.2f} (smallest without false admission)", margin >= f_safe),
                  ("audit, U0", nom & (res[f"q10_U0_{model}"] >= FLOOR).to_numpy()),
                  ("audit, U3 (reference)", ref)]
        for name, adm in rules:
            rows.append(dict(law=law, rule=name, admitted=int(adm.sum()),
                             admitted_but_fail_U3=int((adm & ~ref).sum()),
                             rejected_but_pass_U3=int((~adm & ref).sum()),
                             share_of_admitted_failing_U3=float((adm & ~ref).sum() / max(adm.sum(), 1))))
        m = margin[ref]
        rows.append(dict(law=law, rule="margin of the U3-admitted candidates: minimum / median",
                         admitted=int(ref.sum()), admitted_but_fail_U3=0, rejected_but_pass_U3=0,
                         share_of_admitted_failing_U3=0.0, margin_min=float(m.min()), margin_median=float(np.median(m)),
                         margin_max_of_rejected=float(margin[nom & ~ref].max())))
    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(OUT, "E29_decision_rule_comparison.csv"), index=False, float_format="%.5g")
    with pd.option_context("display.width", 220, "display.max_columns", 20):
        print(df.to_string(index=False))


if __name__ == "__main__":
    main()
