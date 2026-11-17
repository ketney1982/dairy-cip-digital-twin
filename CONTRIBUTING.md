<!-- Author: Ketney Otto
     Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
     Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154 -->

# Contributing

This repository is a public scientific proof-of-concept for a dairy CIP digital
twin. Contributions should preserve reproducibility, synthetic-data labelling,
and the separation between deterministic MATLAB/Simulink computation and the
optional Gemini decision-support layer.

## Development Rules

- Run MATLAB from the repository root and add `src/` to the path.
- Keep model coefficients in `src/cip_model_params.m` and workflow metadata in
  `src/cip_parameters.m`; do not duplicate parameter values across scripts.
- Do not use `assignin` or globals. Pass Simulink variables through
  `Simulink.SimulationInput`.
- Gemini must remain optional and mockable through `CIP_GEMINI_MODE=mock`; it
  must not be called from Simulink solvers or optimization loops.
- Preserve the synthetic-data disclaimer in public datasets, figures, tables,
  reports, and generated documentation.

## Checks Before a Public Change

```matlab
addpath('src')
setenv('CIP_GEMINI_MODE','mock')
setenv('CIP_N_SCENARIOS','50')
run('src/run_full_pipeline.m')
run('src/validate_outputs.m')
```

Also run:

```powershell
python tools/check_author_headers.py
git diff --check
```

For full manuscript artifact updates, run the canonical 5000-scenario pipeline
and document regenerated `data/`, `results/`, `figures/`, or `tables/` files in
`docs/public_release_manifest.md`.
