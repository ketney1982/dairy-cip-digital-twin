% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function flags = cip_pareto_2d_fronts(T)
%CIP_PARETO_2D_FRONTS  2D non-dominated membership for the manuscript Pareto panels.
%   FLAGS = CIP_PARETO_2D_FRONTS(T) takes the Pareto-solutions table T (with the
%   objective columns water_L, total_energy_kWh, COD_mgL, CO2eq_kg,
%   cleaning_score, EHPI) and returns a table of logical columns, one per 2D
%   projection drawn in manuscript Fig 6, marking the points that are
%   non-dominated in that projection. x is always minimised; y is minimised or
%   maximised per panel.
%
%   This is the SINGLE SOURCE OF TRUTH for the 2D-front overlay: the Python
%   figure code reads these flags rather than recomputing them, so every value
%   drawn traces back to MATLAB. All data are SIMULATION-GENERATED SYNTHETIC
%   (proof-of-concept; coefficients not calibrated against plant data).

    % name                xCol        yCol               yMinimise
    specs = {
        'front_water_energy', 'water_L',  'total_energy_kWh', true
        'front_COD_cleaning', 'COD_mgL',  'cleaning_score',   false
        'front_CO2_cleaning', 'CO2eq_kg', 'cleaning_score',   false
        'front_water_EHPI',   'water_L',  'EHPI',             false
        };

    flags = table();
    for i = 1:size(specs, 1)
        name = specs{i, 1};
        xk   = specs{i, 2};
        yk   = specs{i, 3};
        yMin = specs{i, 4};
        if ismember(xk, T.Properties.VariableNames) && ...
                ismember(yk, T.Properties.VariableNames)
            flags.(name) = localNonDominated2D(T.(xk), T.(yk), true, yMin);
        end
    end
end


function keep = localNonDominated2D(x, y, xMin, yMin)
%LOCALNONDOMINATED2D  Logical mask of points non-dominated in 2D (x, y).
%   Mirrors the convention of the prior Python filter_2d_pareto: a point i is
%   dominated if some point j is no worse on both axes and strictly better on
%   at least one. Directions are normalised to "smaller is better".
    x = x(:); y = y(:);
    if ~xMin, x = -x; end
    if ~yMin, y = -y; end
    n = numel(x);
    keep = true(n, 1);
    for i = 1:n
        for j = 1:n
            if i == j; continue; end
            dom = (x(j) <= x(i)) && (y(j) <= y(i)) && ...
                  ((x(j) < x(i)) || (y(j) < y(i)));
            if dom
                keep(i) = false;
                break;
            end
        end
    end
end
