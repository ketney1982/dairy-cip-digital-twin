% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function S = cip_policy_scores(T)
%CIP_POLICY_SCORES  Min-max performance scores (0-100) for the policy portfolio.
%   S = CIP_POLICY_SCORES(T) takes the policy-portfolio table T and returns a
%   table with one score_<metric> column per objective, min-max normalised
%   across the FEASIBLE profiles with burdens inverted so that higher always
%   means better (the encoding drawn in manuscript Fig 8). Scores for any
%   infeasible profile are NaN.
%
%   This is the SINGLE SOURCE OF TRUTH for the Fig 8 colour scores: the Python
%   figure code reads these columns rather than recomputing the normalisation,
%   so every value drawn traces back to MATLAB. All data are
%   SIMULATION-GENERATED SYNTHETIC (proof-of-concept; not calibrated).

    objs         = {'water_L', 'total_energy_kWh', 'COD_mgL', 'CO2eq_kg', ...
                    'cleaning_score', 'EHPI'};
    higherBetter = {'cleaning_score', 'EHPI'};

    if ismember('feasible', T.Properties.VariableNames)
        feas = logical(T.feasible);
    else
        feas = true(height(T), 1);
    end

    S = table();
    for k = 1:numel(objs)
        o = objs{k};
        if ~ismember(o, T.Properties.VariableNames); continue; end
        col = T.(o);
        lo = min(col(feas));
        hi = max(col(feas));
        span = hi - lo;
        if ~(span > 0); span = 1; end
        z = (col - lo) / span;
        if ~ismember(o, higherBetter)
            z = 1 - z;                       % invert burdens: lower raw -> higher score
        end
        sc = 100 * z;
        sc(~feas) = NaN;
        S.(['score_' o]) = sc;
    end
end
