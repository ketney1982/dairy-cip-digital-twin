% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function augment_figure_derived()
%AUGMENT_FIGURE_DERIVED  Add MATLAB-computed derived columns to existing result
%   CSVs so the Python manuscript figures read them instead of recomputing:
%     * 2D Pareto-front membership flags   -> results/pareto_solutions.csv (Fig 6)
%     * min-max performance scores (0-100) -> results/policy_portfolio_results.csv (Fig 8)
%
%   It operates IN PLACE on the current artifacts and does NOT re-run the
%   (stochastic) Pareto optimisation, so the exact solution points are
%   preserved. The same computations are also wired into optimize_cip_pareto.m
%   and run_policy_portfolio.m for future full runs; this script only migrates
%   already-written CSVs. Idempotent — safe to run repeatedly.
%
%   All data are SIMULATION-GENERATED SYNTHETIC (proof-of-concept; not calibrated).

    here   = fileparts(mfilename('fullpath'));
    addpath(here);
    resDir = fullfile(here, '..', 'results');

    pCsv = fullfile(resDir, 'pareto_solutions.csv');
    if isfile(pCsv)
        T = readtable(pCsv);
        flags = cip_pareto_2d_fronts(T);
        for v = flags.Properties.VariableNames
            T.(v{1}) = double(flags.(v{1}));     % 0/1 for unambiguous CSV parsing
        end
        writetable(T, pCsv);
        fprintf('[augment] Pareto 2D-front flags -> %s (%d columns)\n', pCsv, width(T));
    else
        fprintf('[augment] skipped Pareto (missing %s)\n', pCsv);
    end

    qCsv = fullfile(resDir, 'policy_portfolio_results.csv');
    if isfile(qCsv)
        T2 = readtable(qCsv);
        S = cip_policy_scores(T2);
        for v = S.Properties.VariableNames
            T2.(v{1}) = S.(v{1});
        end
        writetable(T2, qCsv);
        fprintf('[augment] Policy performance scores -> %s (%d columns)\n', qCsv, width(T2));
    else
        fprintf('[augment] skipped policy (missing %s)\n', qCsv);
    end
end
