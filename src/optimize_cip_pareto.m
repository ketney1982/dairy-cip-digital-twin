% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% OPTIMIZE_CIP_PARETO  Multi-objective Pareto optimization of CIP recipes.
%
%   Uses the trained ML surrogates to search for environmentally efficient CIP
%   recipes that trade off water, energy, COD and CO2 against cleaning quality.
%
%   Objectives (all minimized): water_L, total_energy_kWh, COD_mgL, CO2eq_kg,
%   and -cleaning_score (i.e. maximize cleaning). Constraint: cleaning_score
%   must meet the hygiene floor (>= 95, or a stricter policy value).
%
%   GOVERNANCE: Gemini is NEVER called from this script or inside the optimizer.
%   A policy file produced earlier by gemini_policy_translator may supply the
%   numeric constraints/weights, but the optimization itself is purely numeric.
%
%   METHODOLOGICAL NOTE ON soil0:
%   soil0 (initial soiling) is a process UNCERTAINTY condition, not an operator
%   setpoint. By default (FIX_SOIL0 = true) it is held fixed at a representative
%   value and the optimizer searches only the 9 operator-controllable variables
%   (P.operational_vars). A documented code path (FIX_SOIL0 = false) optimizes
%   all 10 variables for sensitivity studies.
%
%   Output: results/pareto_solutions.csv. MATLAB Pareto figures are optional
%   and disabled by default because manuscript figures are rendered in Python.
%
%   See also: TRAIN_SURROGATE_MODELS, GEMINI_POLICY_TRANSLATOR, PLOT_RESULTS.

%% ----- Paths and surrogates -------------------------------------------------
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here);
P = cip_parameters();

resDir = fullfile(root,'results'); if ~exist(resDir,'dir'); mkdir(resDir); end
figDir = fullfile(root,'figures'); if ~exist(figDir,'dir'); mkdir(figDir); end
matPath = fullfile(resDir,'surrogate_models.mat');
outCsv  = fullfile(resDir,'pareto_solutions.csv');

if exist(matPath,'file') ~= 2
    error('optimize_cip_pareto:noModels','Surrogate models not found:\n  %s\nRun train_surrogate_models first.', matPath);
end
S = load(matPath);                 % models, predictors, targets
models = S.models; predictors = S.predictors;
reqT = {'water_L','total_energy_kWh','COD_mgL','CO2eq_kg','cleaning_score','EHPI'};
for k = 1:numel(reqT)
    if ~isfield(models, reqT{k})
        error('optimize_cip_pareto:missingModel','Surrogate for %s is missing.', reqT{k});
    end
end

%% ----- Decision space (with soil0 handling) ---------------------------------
% FIX_SOIL0: when true (default), soil0 is held fixed as a representative
% uncertainty condition and the optimizer searches only the 9 operator-controlled
% variables. Set CIP_FIX_SOIL0=false to optimize all 10 variables for sensitivity
% studies (documented path; makes both branches reachable). Default true.
FIX_SOIL0   = localEnvBool('CIP_FIX_SOIL0', true);
soil0_fixed = 0.5;      % representative initial soiling for operational study
soilIdx = find(strcmp(P.var_names,'soil0'),1);

lbFull = P.lb; ubFull = P.ub;
if FIX_SOIL0
    effCols = setdiff(1:numel(P.var_names), soilIdx);
    lbEff = lbFull(effCols); ubEff = ubFull(effCols);
else
    effCols = 1:numel(P.var_names);
    lbEff = lbFull; ubEff = ubFull;
end
nvars = numel(lbEff);

%% ----- Policy-derived constraints / weights ---------------------------------
% DESIGN CHOICE (documented): gamultiobj enforces ONLY the two constraints that
% shape a meaningful global Pareto front - the hygiene floor (min_cleaning_score)
% and, if set, the COD cap (max_COD_mgL). The remaining policy caps
% (max_water_L, max_total_energy_kWh, max_CO2eq_kg, max_hygienic_risk) are NOT
% applied here on purpose: the optimizer produces a broad, policy-agnostic front,
% and the context-specific caps are enforced DOWNSTREAM by the deterministic
% safety gate in ai_supervisory_control_recommender (and as filters in
% run_policy_portfolio). This keeps one reusable front while letting many
% policies select/gate from it. To instead bake the caps into the front, add
% them to localNonlcon.
min_cleaning = P.min_cleaning_score;     % hard floor 95 enforced below
max_COD      = inf;
% Objective weights for POST-HOC balanced selection only (NOT inside gamultiobj).
wsel = struct('water_L',0.25,'total_energy_kWh',0.20,'COD_mgL',0.25, ...
              'CO2eq_kg',0.20,'cleaning_score',0.10);
policyPath = fullfile(resDir,'selected_policy_config.json');
if exist(policyPath,'file')==2
    try
        cfg = jsondecode(fileread(policyPath));
        % jsondecode maps JSON null/[] to an empty array, so each numeric field
        % is coerced to a finite scalar (or a default) before use to avoid
        % "operands must be logical scalars" errors on empty/non-scalar values.
        if isfield(cfg,'constraints')
            mc = localScalarOr(cfg.constraints, 'min_cleaning_score', min_cleaning);
            if isfinite(mc); min_cleaning = mc; end
            codCap = localScalarOr(cfg.constraints, 'max_COD_mgL', NaN);
            if isfinite(codCap) && codCap > 0; max_COD = codCap; end
        end
        if isfield(cfg,'objective_weights')
            for f = fieldnames(wsel).'
                wv = localScalarOr(cfg.objective_weights, f{1}, NaN);
                if isfinite(wv); wsel.(f{1}) = wv; end
            end
        end
        fprintf('[optimize_cip_pareto] Applied policy config (%s).\n', policyPath);
    catch ME
        warning('optimize_cip_pareto:policy','Could not read policy config: %s', ME.message);
    end
end
min_cleaning = max(95, min_cleaning);     % governance hard floor
fprintf('[optimize_cip_pareto] Hygiene floor cleaning_score >= %.1f ; max_COD = %g\n', min_cleaning, max_COD);
% NOTE: a hygienic_risk surrogate IS trained (hygienic_risk is in P.targets), but
% the hygienic cap is enforced by the downstream safety gate, not inside
% gamultiobj (see the DESIGN CHOICE note above). In the feasible region
% (cleaning_score >= 95) hygienic_risk is collinear with cleaning_score, so the
% hygiene floor already constrains it here; the explicit max_hygienic_risk cap is
% applied per-candidate by ai_supervisory_control_recommender.

%% ----- Objective and constraint handles (vectorized) ------------------------
objHandle = @(X) localObj(X, models, predictors, effCols, soilIdx, soil0_fixed, FIX_SOIL0, numel(P.var_names));
nlHandle  = @(X) localNonlcon(X, models, predictors, effCols, soilIdx, soil0_fixed, FIX_SOIL0, numel(P.var_names), min_cleaning, max_COD);

%% ----- Optimize (gamultiobj if available, else sampling fallback) -----------
hasGADS = license('test','GADS_Toolbox') && exist('gamultiobj','file')==2;
rng(42);
% Population / generation counts default to the canonical study values. They may
% be reduced via the optional CIP_GA_POP / CIP_GA_MAXGEN environment variables so
% an iterative driver (run_ai_closed_loop_study) can run many faster passes; the
% stable classic pipeline leaves them unset and keeps the 200/150 defaults.
gaPop = localEnvNum('CIP_GA_POP', 200);
gaGen = localEnvNum('CIP_GA_MAXGEN', 150);
if hasGADS
    opts = optimoptions('gamultiobj', ...
        'UseVectorized',true, ...
        'PopulationSize',gaPop, ...
        'MaxGenerations',gaGen, ...
        'ParetoFraction',0.35, ...
        'Display','iter');
    [xeff, ~] = gamultiobj(objHandle, nvars, [],[],[],[], lbEff, ubEff, nlHandle, opts);
    method = 'gamultiobj';
else
    warning('optimize_cip_pareto:noGADS', ...
        'Global Optimization Toolbox unavailable; using sampling + non-dominated filter fallback.');
    M = 12000;
    Xs = lbEff + rand(M,nvars).*(ubEff - lbEff);
    F  = objHandle(Xs);
    [c,~] = nlHandle(Xs);
    feas = all(c <= 0, 2);
    Xs = Xs(feas,:); F = F(feas,:);
    if isempty(Xs)
        error('optimize_cip_pareto:infeasible','No feasible samples; relax constraints.');
    end
    nd = localParetoFilter(F);
    xeff = Xs(nd,:);
    method = 'sampling+paretoFilter';
end
nSol = size(xeff,1);
fprintf('[optimize_cip_pareto] Method=%s, Pareto solutions=%d\n', method, nSol);

%% ----- Predicted metrics for each Pareto solution ---------------------------
Xfull = localExpand(xeff, effCols, soilIdx, soil0_fixed, FIX_SOIL0, numel(P.var_names));
pr = localPredictAll(models, predictors, Xfull);

%% ----- Balanced selection (weighted normalized objectives) ------------------
nWater = localNorm(pr.water_L);
nEnergy= localNorm(pr.total_energy_kWh);
nCOD   = localNorm(pr.COD_mgL);
nCO2   = localNorm(pr.CO2eq_kg);
costClean = 1 - localNorm(pr.cleaning_score);     % lower is better
wv = [wsel.water_L, wsel.total_energy_kWh, wsel.COD_mgL, wsel.CO2eq_kg, wsel.cleaning_score];
wv = wv / max(sum(wv),eps);
score = wv(1)*nWater + wv(2)*nEnergy + wv(3)*nCOD + wv(4)*nCO2 + wv(5)*costClean;

selection_label = strings(nSol,1);
selection_label(:) = "";
[~,iBal]   = min(score);             selection_label(iBal)   = appendLabel(selection_label(iBal),"balanced");
[~,iWat]   = min(pr.water_L);        selection_label(iWat)   = appendLabel(selection_label(iWat),"lowest_water");
[~,iEne]   = min(pr.total_energy_kWh);selection_label(iEne)  = appendLabel(selection_label(iEne),"lowest_energy");
[~,iCOD]   = min(pr.COD_mgL);        selection_label(iCOD)   = appendLabel(selection_label(iCOD),"lowest_COD");
[~,iCln]   = max(pr.cleaning_score); selection_label(iCln)   = appendLabel(selection_label(iCln),"highest_cleaning");

%% ----- Assemble and save solutions table ------------------------------------
Tbl = array2table(Xfull, 'VariableNames', P.var_names);
Tbl.water_L          = pr.water_L;
Tbl.total_energy_kWh = pr.total_energy_kWh;
Tbl.COD_mgL          = pr.COD_mgL;
Tbl.CO2eq_kg         = pr.CO2eq_kg;
Tbl.cleaning_score   = pr.cleaning_score;
Tbl.EHPI             = pr.EHPI;
Tbl.weighted_score   = score;
Tbl.selection_label  = cellstr(selection_label);

% 2D Pareto-front membership for the manuscript figures (computed here so the
% Python plots read it rather than recomputing — single source of truth).
fronts2d = cip_pareto_2d_fronts(Tbl);
for vv = fronts2d.Properties.VariableNames
    Tbl.(vv{1}) = double(fronts2d.(vv{1}));
end

writetable(Tbl, outCsv);
fprintf('[optimize_cip_pareto] Saved Pareto solutions -> %s\n', outCsv);

%% ----- Optional MATLAB Pareto figures --------------------------------------
if localEnvBool('CIP_MATLAB_FIGURES', false)
    localScatterFig(pr.water_L, pr.total_energy_kWh, pr.cleaning_score, ...
        'Water use (L)','Total energy (kWh)','cleaning (%)', ...
        'Pareto front: water vs energy (SYNTHETIC)', fullfile(figDir,'fig_pareto_water_energy.png'));
    localScatterFig(pr.COD_mgL, pr.cleaning_score, pr.total_energy_kWh, ...
        'COD (mg/L)','Cleaning score (%)','energy (kWh)', ...
        'Pareto front: COD vs cleaning (SYNTHETIC)', fullfile(figDir,'fig_pareto_cod_cleaning.png'));
    localScatterFig(pr.CO2eq_kg, pr.cleaning_score, pr.water_L, ...
        'CO_2eq (kg)','Cleaning score (%)','water (L)', ...
        'Pareto front: CO2eq vs cleaning (SYNTHETIC)', fullfile(figDir,'fig_pareto_co2_cleaning.png'));
    localScatterFig(pr.water_L, pr.EHPI, pr.cleaning_score, ...
        'Water use (L)','EHPI (proposed index)','cleaning (%)', ...
        'Pareto front: EHPI vs water (SYNTHETIC)', fullfile(figDir,'fig_pareto_ehpi_water.png'));
else
    fprintf('[optimize_cip_pareto] Skipped MATLAB Pareto figures (Python manuscript figures use pareto_solutions.csv).\n');
end

fprintf('[optimize_cip_pareto] Done. Balanced solution row = %d (label set).\n', iBal);

%% ===== Local functions ======================================================
function Xf = localExpand(Xeff, effCols, soilIdx, soil0_fixed, FIX_SOIL0, nFull)
    if FIX_SOIL0
        m = size(Xeff,1);
        Xf = zeros(m, nFull);
        Xf(:,effCols) = Xeff;
        Xf(:,soilIdx) = soil0_fixed;
    else
        Xf = Xeff;
    end
end

function pr = localPredictAll(models, predictors, Xfull)
    Tb = array2table(Xfull, 'VariableNames', predictors);
    pr.water_L          = max(0, predict(models.water_L, Tb));
    pr.total_energy_kWh = max(0, predict(models.total_energy_kWh, Tb));
    pr.COD_mgL          = max(0, predict(models.COD_mgL, Tb));
    pr.CO2eq_kg         = max(0, predict(models.CO2eq_kg, Tb));
    % Clamp cleaning to the physical [0,100] ceiling; the ensemble can
    % extrapolate marginally past 100 near the boundary of the training data.
    pr.cleaning_score   = min(100, max(0, predict(models.cleaning_score, Tb)));
    pr.EHPI             = max(0, predict(models.EHPI, Tb));
end

function v = localScalarOr(s, field, default)
%LOCALSCALAROR Return a finite scalar from struct field, else the default.
%   Coerces JSON-decoded empties/arrays to a single value so short-circuit
%   logical tests downstream never see a non-scalar operand.
    v = default;
    if isfield(s, field)
        x = s.(field);
        if isnumeric(x) && isscalar(x)
            v = x;
        elseif isnumeric(x) && ~isempty(x)
            v = x(1);   % collapse unexpected arrays to their first element
        end
    end
end

function v = localEnvNum(name, default)
%LOCALENVNUM Return a positive finite integer from an env var, else the default.
    v = default;
    s = getenv(name);
    if ~isempty(s)
        x = str2double(s);
        if isfinite(x) && x >= 1; v = round(x); end
    end
end

function v = localEnvBool(name, default)
%LOCALENVBOOL Return a logical from an env var ('true'/'1' -> true, 'false'/'0' -> false).
    v = default;
    s = lower(strtrim(getenv(name)));
    if strcmp(s,'true') || strcmp(s,'1')
        v = true;
    elseif strcmp(s,'false') || strcmp(s,'0')
        v = false;
    end
end

function F = localObj(Xeff, models, predictors, effCols, soilIdx, soil0_fixed, FIX_SOIL0, nFull)
    Xf = localExpand(Xeff, effCols, soilIdx, soil0_fixed, FIX_SOIL0, nFull);
    pr = localPredictAll(models, predictors, Xf);
    F = [pr.water_L, pr.total_energy_kWh, pr.COD_mgL, pr.CO2eq_kg, -pr.cleaning_score];
end

function [c, ceq] = localNonlcon(Xeff, models, predictors, effCols, soilIdx, soil0_fixed, FIX_SOIL0, nFull, min_cleaning, max_COD)
    Xf = localExpand(Xeff, effCols, soilIdx, soil0_fixed, FIX_SOIL0, nFull);
    pr = localPredictAll(models, predictors, Xf);
    c = min_cleaning - pr.cleaning_score;          % <= 0 feasible
    if isfinite(max_COD)
        c = [c, pr.COD_mgL - max_COD];
    end
    ceq = [];
end

function nd = localParetoFilter(F)
%LOCALPARETOFILTER Non-dominated set for minimization (archive method).
%   arch is preallocated to its maximum possible size (n) and tracked with a
%   live count na, so it never resizes inside the loop (no AGROW).
    n = size(F,1);
    nd = false(n,1);
    arch = zeros(1,n);         % preallocated index archive (<= n non-dominated)
    na   = 0;                  % live archive count
    for ii = 1:n
        fi = F(ii,:);
        if na == 0
            na = 1; arch(1) = ii; continue;
        end
        idx = arch(1:na);
        FA  = F(idx,:);
        le = FA <= fi; lt = FA < fi;
        if any(all(le,2) & any(lt,2)); continue; end   % fi dominated -> drop it
        ge = FA >= fi; gt = FA > fi;
        keep = ~(all(ge,2) & any(gt,2));               % drop archive entries fi dominates
        nk = sum(keep);
        arch(1:nk) = idx(keep);
        na = nk + 1;
        arch(na) = ii;
    end
    nd(arch(1:na)) = true;
end

function y = localNorm(x)
    x = x(:); lo = min(x); hi = max(x);
    if hi - lo <= eps; y = zeros(size(x)); else; y = (x - lo) / (hi - lo); end
end

function s = appendLabel(s, lab)
    if strlength(s)==0; s = lab; else; s = s + "+" + lab; end
end

function localScatterFig(x, y, cdata, xl, yl, cl, ttl, outPath)
    f = figure('Visible','off','Position',[100 100 720 540]);
    scatter(x, y, 36, cdata, 'filled', 'MarkerFaceAlpha',0.75);
    grid on; box on;
    xlabel(xl); ylabel(yl); title(ttl);
    cb = colorbar; cb.Label.String = cl;
    set(gca,'FontSize',12);
    try
        exportgraphics(f, outPath, 'Resolution',200);
    catch
        saveas(f, outPath);
    end
    close(f);
end
