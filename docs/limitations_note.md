<!-- Author: Ketney Otto
     Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
     Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154 -->

# Limitations Note

This project is a **proof-of-concept simulation framework**. The following
limitations are explicit and must be stated in any derived report or manuscript.

1. **Synthetic data are not real measurements.** Every value originates from a
   simplified mechanistic simulation with uncalibrated coefficients. None of it
   reflects a specific real dairy plant.

2. **COD equations are simplified.** Organic `COD_mgL` is a linear proxy of the
   cumulative soil mass removed (`soil0 - soil`), not a calibrated effluent
   chemistry model. Real wastewater chemistry (fat/protein/lactose dynamics, pH,
   temperature effects, dilution and treatment boundary conditions) is far more
   complex.

3. **The NaOH residual model is approximate and separated from organic COD.**
   Residual carry-over is represented by phase-dependent factors rather than a
   mechanistic rinsing/diffusion model. `COD_chem_equiv_mgL` may be reported as
   a separate simplification, but inorganic NaOH residual is not added to
   organic `COD_mgL`.

4. **`cleaning_score` is a model-derived proxy, not microbiological validation.**
   It is computed from residual soil fraction and does **not** represent ATP,
   microbial counts, or any food-safety verification.

5. **EHPI is a proposed index, not a standardized metric.** The
   Environmental–Hygienic Performance Index combines normalized burdens with
   ad-hoc weights and normalization constants; it has no regulatory standing.

6. **Gemini cannot validate the physical correctness of the model.** The
   generative-AI layer operates on text and summary statistics; it cannot verify
   mass/energy balances or reaction kinetics and may produce confident errors.

7. **Gemini outputs must be reviewed by a human domain expert.** Policy
   translations, plausibility flags and management explanations are decision
   *support*, not decisions. No automatic recalibration is performed.

8. **Not for operational control.** The model must **not** be used to control or
   set CIP parameters in a real plant without industrial calibration, independent
   verification, and food-safety/HACCP validation.

### Agentic AI-supervised extension — additional limitations

9. **AI-proposed hypotheses and experiments are not validated science.** They are
   only tested **deterministically inside the simulator**. A "supported"
   hypothesis holds for the synthetic model, not necessarily for a real plant.

10. **The closed loop adds synthetic data to synthetic data.** AI-designed
    scenarios are simulated by the same uncalibrated twin and folded back into
    training. This explores the model's own behaviour and improves surrogate
    coverage, but introduces **no new real-world information** and cannot reduce
    real-world uncertainty.

11. **The supervisory recommendation is virtual and research-only.** The safety
    gate operates on **surrogate predictions**, not measurements; passing the
    gate is **not** a safety guarantee. `not_for_real_time_control` is always
    true and `human_approval_required` is always true.

12. **Model-audit flags are AI-generated prompts for human review,** not verified
    defects. No parameter or equation is changed automatically. The revised
    `soil0 → COD` coupling is a synthetic cumulative-soil proxy and still
    requires expert calibration; NaOH residual remains a separate approximate
    carry-over proxy rather than a true wastewater chemistry model.

13. **LIVE Gemini can return malformed or truncated JSON.** When it does, the
    affected module falls back to a clearly-labelled deterministic **MOCK**
    output. Consequently a run may be **MIXED** (some LIVE, some MOCK) even with
    an API key configured — always check `results/run_manifest.json`
    (`gemini_mode`) before interpreting the generative-AI artifacts.

14. **`hygienic_risk` and `cleaning_score` remain model-derived proxies.** A
    surrogate is trained for `hygienic_risk` so the gate can enforce a numeric
    cap, but it is still derived from residual soil, not microbiology.

15. **Uncertainty intervals are SURROGATE uncertainty, not measurement
    uncertainty.** The quantile regression forests quantify how confidently the
    surrogate reproduces the *simulator*; on this low-noise synthetic data the
    90% intervals tend to over-cover (≈0.99), i.e. they are conservative. They
    say nothing about how well the simulator matches a real plant.

16. **Passing the safety shield is a synthetic feasibility check, not a safety
    guarantee.** The shield enforces hard constraints on conservative surrogate
    bounds; clearing it does not certify food safety. Conversely, under strict
    policies the shield may reject every candidate — an honest "not robustly
    safe under uncertainty" verdict, not a software fault.

17. **Counterfactuals are surrogate-predicted, hence associational-through-a-
    learned-model.** The mechanistic twin defines the causal structure; the
    counterfactual engine predicts intervened outcomes via surrogates of that
    twin. For exact mechanistic effects, re-simulate the intervened recipes.

---

**Framing.** The framework is intended to demonstrate an architecture —
mechanistic simulation → ML surrogate → Pareto optimization → governed
generative-AI decision support — and to provide a reproducible starting point for
later calibration with industrial or literature data and subsequent manuscript
development. All claims should remain qualified as *simulation-based* and
*proof-of-concept* until such calibration and validation are completed.
