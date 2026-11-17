% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% RUN_COUNTERFACTUAL_CIP_STUDY  What-if interventions on a baseline CIP recipe.
%
%   Applies controlled, single-factor (and a few combined) INTERVENTIONS to a
%   baseline recipe and reports their effect on water_L, total_energy_kWh,
%   COD_mgL, CO2eq_kg, cleaning_score and hygienic_risk, with surrogate
%   uncertainty intervals. This is a counterfactual ("what would happen if we
%   changed X?") analysis over the digital twin's input space.
%
%   Interventions: t_alk -10% / -20%; T_C +3 / +5 degC; water_rec +0.15;
%   NaOH_pct -20%; plus two compromise combinations.
%
%   Causal framing: the mechanistic Simulink twin defines the input->output
%   causal structure; here we predict the intervened outcomes with the ML
%   surrogates that APPROXIMATE that twin (R^2 > 0.95). For exact mechanistic
%   effects, re-simulate the intervened recipes with run_ai_designed_scenarios.
%
%   >>> SIMULATION-GENERATED SYNTHETIC surrogate predictions. NOT real plant
%   responses; for hypothesis generation and screening only. <<<
%
%   Outputs:
%     results/counterfactual_cip_results.csv
%     results/counterfactual_cip_report.md
%
%   See also: TRAIN_SURROGATE_MODELS, TRAIN_UNCERTAINTY_SURROGATES, SAFETY_SHIELD.

here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here);
P = cip_parameters();
resDir = fullfile(root,'results'); if ~exist(resDir,'dir'); mkdir(resDir); end
outCsv = fullfile(resDir,'counterfactual_cip_results.csv');
outMd  = fullfile(resDir,'counterfactual_cip_report.md');

matPath = fullfile(resDir,'surrogate_models.mat');
if exist(matPath,'file') ~= 2
    error('run_counterfactual_cip_study:noModels', ...
        'Surrogate models not found:\n  %s\nRun train_surrogate_models first.', matPath);
end
S = load(matPath); models = S.models; predictors = S.predictors;
tgts = {'cleaning_score','COD_mgL','water_L','total_energy_kWh','CO2eq_kg','hygienic_risk'};

% Optional uncertainty surrogates for intervals.
unc = [];
uncPath = fullfile(root,'models','uncertainty_surrogates.mat');
if exist(uncPath,'file')==2
    try
        unc = load(uncPath);
    catch
        unc = [];
    end
end

%% ----- Baseline recipe -----------------------------------------------------
base = localBaselineRecipe(resDir, root, P);
fprintf('[run_counterfactual_cip_study] Baseline: T_C=%.1f Q=%.2f t_alk=%.0f NaOH=%.2f water_rec=%.2f\n', ...
    base.T_C, base.Q_m3h, base.t_alk, base.NaOH_pct, base.water_rec);

%% ----- Define interventions (clamped to bounds) ----------------------------
iv = {};
iv{end+1} = localIntv('baseline',              base, {}, P);
iv{end+1} = localIntv('t_alk_-10%',            base, {'t_alk', base.t_alk*0.90}, P);
iv{end+1} = localIntv('t_alk_-20%',            base, {'t_alk', base.t_alk*0.80}, P);
iv{end+1} = localIntv('T_C_+3C',               base, {'T_C',   base.T_C + 3}, P);
iv{end+1} = localIntv('T_C_+5C',               base, {'T_C',   base.T_C + 5}, P);
iv{end+1} = localIntv('water_rec_+0.15',       base, {'water_rec', base.water_rec + 0.15}, P);
iv{end+1} = localIntv('NaOH_pct_-20%',         base, {'NaOH_pct', base.NaOH_pct*0.80}, P);
iv{end+1} = localIntv('T_C_+5C_&_t_alk_-15%',  base, {'T_C', base.T_C+5, 't_alk', base.t_alk*0.85}, P);
iv{end+1} = localIntv('water_rec_+0.15_&_T_C_+3C', base, {'water_rec', base.water_rec+0.15, 'T_C', base.T_C+3}, P);
nIv = numel(iv);

%% ----- Predict outcomes (mean + interval) ----------------------------------
X = zeros(nIv, numel(P.var_names));
for i = 1:nIv; X(i,:) = iv{i}.x; end
Tb = array2table(X, 'VariableNames', predictors);
mu = struct(); lo = struct(); hi = struct();
for k = 1:numel(tgts)
    t = tgts{k};
    [lo.(t), med, hi.(t)] = localInterval(unc, t, X, nIv);
    % Use the quantile MEDIAN (q50) as the reported mean when an uncertainty
    % surrogate exists, so mu is guaranteed within [lower, upper]. Fall back to
    % the point surrogate only when no quantile model is available for t.
    if any(isfinite(med))
        mu.(t) = med;
    elseif isfield(models, t)
        mu.(t) = localClamp(t, predict(models.(t), Tb));
    else
        mu.(t) = nan(nIv,1);
    end
end

%% ----- Deltas vs baseline + feasibility ------------------------------------
b = 1;   % baseline row
labels = strings(nIv,1); for i=1:nIv; labels(i)=string(iv{i}.label); end
% Conservative cleaning lower bound (kept for display/fallback).
cleanLB = lo.cleaning_score;
useMean = ~isfinite(cleanLB);
cleanLB(useMean) = mu.cleaning_score(useMean);
% FEASIBILITY via the deterministic safety_shield: each intervention must clear
% the FULL active policy (hygiene floor AND any finite max_COD_mgL / max_water_L
% / max_total_energy_kWh / max_CO2eq_kg / max_hygienic_risk) on CONSERVATIVE
% bounds - not just the cleaning floor. Falls back to the cleaning lower bound
% only if the shield is unavailable.
feasible = false(nIv,1);
shieldOpts = struct('unc', unc, 'policy_path', fullfile(resDir,'selected_policy_config.json'));
for i = 1:nIv
    recI = struct();
    for k = 1:numel(P.var_names); recI.(P.var_names{k}) = X(i,k); end
    try
        shi = safety_shield(recI, shieldOpts);
        feasible(i) = shi.gate_passed;
    catch
        feasible(i) = cleanLB(i) >= P.min_cleaning_score;   % fallback
    end
end

% APPLIED delta per intervention: the label states the REQUESTED change, but
% values are clamped to P.lb/P.ub, so the realized change can be smaller. Record
% "var: baseline -> applied (delta)" for each changed variable, for transparency.
applied = strings(nIv,1);
for i = 1:nIv
    ch = iv{i}.changed;
    if isempty(ch); applied(i) = "(baseline)"; continue; end
    parts = strings(1, numel(ch));
    for j = 1:numel(ch)
        vi = find(strcmp(P.var_names, ch{j}), 1);
        b0 = X(b, vi); va = X(i, vi);
        parts(j) = sprintf('%s: %.4g->%.4g (%+.4g)', ch{j}, b0, va, va - b0);
    end
    applied(i) = strjoin(parts, '; ');
end

% Composite improvement score vs baseline (lower environmental burden + held
% hygiene). Only meaningful for feasible interventions.
impr = localImprovement(mu, b);
impr(~feasible) = -inf;             % infeasible interventions cannot be "best"
impr(b) = -inf;                     % exclude the baseline itself
[~, bestIdx] = max(impr);
if ~isfinite(impr(bestIdx)); bestIdx = b; end

%% ----- Assemble results table ----------------------------------------------
T = array2table(X, 'VariableNames', P.var_names);
T = addvars(T, labels, 'Before', 1, 'NewVariableNames', 'intervention');
T = addvars(T, applied, 'After', 'intervention', 'NewVariableNames', 'applied_delta');
for k = 1:numel(tgts)
    t = tgts{k};
    T.(t) = round(mu.(t),4);
    T.([t '_lower']) = round(lo.(t),4);
    T.([t '_upper']) = round(hi.(t),4);
    d = mu.(t) - mu.(t)(b);
    T.(['d_' t]) = round(d,4);
end
T.feasible = feasible;
T.is_best_compromise = (1:nIv).' == bestIdx;
writetable(T, outCsv);
fprintf('[run_counterfactual_cip_study] %d interventions -> %s\n', nIv-1, outCsv);
fprintf('[run_counterfactual_cip_study] Best compromise: %s\n', labels(bestIdx));

%% ----- Markdown report ------------------------------------------------------
localWriteReport(outMd, T, bestIdx, base, P);
fprintf('[run_counterfactual_cip_study] Report -> %s\n', outMd);

%% ===== Local functions ======================================================
function r = localBaselineRecipe(resDir, root, P)
% Prefer the supervisory selected recipe; else the successful-dataset mean.
    r = [];
    recPath = fullfile(resDir,'ai_supervisory_recommendation.json');
    if exist(recPath,'file')==2
        try
            J = jsondecode(fileread(recPath));
            if isfield(J,'selected_recipe') && isfield(J.selected_recipe,'T_C')
                sr = J.selected_recipe; r = struct();
                for k = 1:numel(P.var_names)
                    nm = P.var_names{k};
                    if isfield(sr,nm); r.(nm) = sr.(nm); end
                end
            end
        catch
            r = [];
        end
    end
    if ~isempty(r) && all(isfield(r, P.var_names)); return; end
    % Fallback: mean of successful base-dataset rows.
    csv = fullfile(root,'data','dairy_cip_synthetic_dataset.csv');
    r = struct();
    if exist(csv,'file')==2
        D = readtable(csv);
        if ismember('simulation_status', D.Properties.VariableNames)
            D = D(string(D.simulation_status)=="success",:);
        end
        for k = 1:numel(P.var_names)
            nm = P.var_names{k};
            if ismember(nm, D.Properties.VariableNames)
                r.(nm) = min(P.ub(k), max(P.lb(k), mean(D.(nm),'omitnan')));
            else
                r.(nm) = (P.lb(k)+P.ub(k))/2;
            end
        end
    else
        for k = 1:numel(P.var_names); r.(P.var_names{k}) = (P.lb(k)+P.ub(k))/2; end
    end
    r.soil0 = 0.5;   % fixed uncertainty condition
end

function s = localIntv(label, base, changes, P)
% Build an intervention: copy baseline, apply field=value changes, clamp.
    s.label = label;
    rec = base;
    s.changed = changes(1:2:end);   % names of the variables this intervention sets
    for j = 1:2:numel(changes)
        rec.(changes{j}) = changes{j+1};
    end
    x = zeros(1, numel(P.var_names));
    for k = 1:numel(P.var_names)
        nm = P.var_names{k};
        v = rec.(nm);
        x(k) = min(P.ub(k), max(P.lb(k), v));    % clamp to bounds
    end
    s.x = x;
end

function y = localClamp(t, y)
    if strcmp(t,'cleaning_score')
        y = min(100,max(0,y));
    elseif strcmp(t,'hygienic_risk')
        y = min(1,max(0,y));
    else
        y = max(0,y);
    end
end

function [lo, med, hi] = localInterval(unc, t, X, n)
    lo = nan(n,1); med = nan(n,1); hi = nan(n,1);
    if isempty(unc) || ~isfield(unc,'qrf') || ~isfield(unc.qrf, t); return; end
    q = unc.quantiles;
    iL = find(abs(q-0.05)<1e-9,1); if isempty(iL); iL=1; end
    iM = find(abs(q-0.50)<1e-9,1); if isempty(iM); iM=ceil(numel(q)/2); end
    iH = find(abs(q-0.95)<1e-9,1); if isempty(iH); iH=numel(q); end
    try
        qq = quantilePredict(unc.qrf.(t), X, 'Quantile', q);
        lo = localClamp(t, qq(:,iL)); med = localClamp(t, qq(:,iM)); hi = localClamp(t, qq(:,iH));
    catch
        % leave NaN
    end
end

function impr = localImprovement(mu, b)
% Higher = better: reduced burdens + maintained/raised cleaning, vs baseline.
    rel = @(t) (mu.(t)(b) - mu.(t)) ./ max(abs(mu.(t)(b)), eps);   % fractional reduction
    burden = 0.25*rel('water_L') + 0.25*rel('total_energy_kWh') + ...
             0.25*rel('COD_mgL') + 0.25*rel('CO2eq_kg');
    cleanGain = (mu.cleaning_score - mu.cleaning_score(b)) / 100;  % small bonus
    impr = burden + 0.5*cleanGain;
end

function localWriteReport(outMd, T, bestIdx, base, P)
    L = {};
    L{end+1} = '<!-- Author: Ketney Otto';
    L{end+1} = '     Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania';
    L{end+1} = '     Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154 -->';
    L{end+1} = '';
    L{end+1} = '# Counterfactual CIP Study (what-if interventions)';
    L{end+1} = '';
    L{end+1} = '> SIMULATION-GENERATED SYNTHETIC surrogate predictions over the digital twin.';
    L{end+1} = '> NOT real plant responses; screening/hypothesis use only. Human approval required.';
    L{end+1} = '';
    L{end+1} = sprintf('**Baseline recipe:** T_C=%.1f C, Q=%.2f m3/h, t_pre=%.0f, t_alk=%.0f, t_int=%.0f, t_final=%.0f s, NaOH=%.2f%%, heat_rec=%.2f, water_rec=%.2f (soil0=%.2f fixed).', ...
        base.T_C, base.Q_m3h, base.t_pre, base.t_alk, base.t_int, base.t_final, base.NaOH_pct, base.heat_rec, base.water_rec, base.soil0);
    L{end+1} = '';
    L{end+1} = '## Effect of each intervention (mean prediction; delta vs baseline)';
    L{end+1} = '';
    L{end+1} = '| Intervention | cleaning | clean_lb | dClean | water_L | dWater | energy | dEnergy | COD | dCOD | CO2eq | dCO2 | hyg_risk | feasible |';
    L{end+1} = '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|';
    for i = 1:height(T)
        L{end+1} = sprintf('| %s | %.1f | %.1f | %+.1f | %.0f | %+.0f | %.2f | %+.2f | %.0f | %+.0f | %.2f | %+.2f | %.3f | %s |', ...
            T.intervention(i), T.cleaning_score(i), T.cleaning_score_lower(i), T.d_cleaning_score(i), ...
            T.water_L(i), T.d_water_L(i), T.total_energy_kWh(i), T.d_total_energy_kWh(i), ...
            T.COD_mgL(i), T.d_COD_mgL(i), T.CO2eq_kg(i), T.d_CO2eq_kg(i), ...
            T.hygienic_risk(i), localYN(T.feasible(i))); %#ok<AGROW>
    end
    L{end+1} = '';
    L{end+1} = '### Applied interventions (after clamping to bounds)';
    L{end+1} = 'The labels above are the *requested* change; values are clamped to P.lb/P.ub, so the *realized* change may be smaller:';
    if ismember('applied_delta', T.Properties.VariableNames)
        for i = 1:height(T)
            L{end+1} = sprintf('- `%s`: %s', T.intervention(i), T.applied_delta(i)); %#ok<AGROW>
        end
    end
    L{end+1} = '';
    L{end+1} = sprintf('**Best compromise (feasible, max burden reduction while holding hygiene):** `%s`.', T.intervention(bestIdx));
    L{end+1} = '';
    L{end+1} = '### Interpretation';
    L{end+1} = '- Raising temperature (T_C) tends to raise cleaning but also energy/CO2.';
    L{end+1} = '- Shortening the alkaline phase (t_alk) saves time/energy but can lower cleaning.';
    L{end+1} = '- Higher water recovery (water_rec) cuts water with little hygiene cost.';
    L{end+1} = '- Lower NaOH reduces chemical load but may reduce cleaning and effluent COD.';
    L{end+1} = sprintf(['- Feasibility is decided by the deterministic safety_shield on CONSERVATIVE ', ...
        'bounds: an intervention is feasible only if it clears the FULL active policy - the %.0f%% ', ...
        'hygiene floor on the cleaning_score lower bound AND every finite cap (COD/water/energy/CO2/', ...
        'hygienic_risk) on the relevant upper bound. A recipe whose mean meets the floor but whose ', ...
        'interval dips below it, or that breaches any cap, is marked NOT feasible.'], P.min_cleaning_score);
    L{end+1} = '';
    L{end+1} = '_Counterfactuals predicted by ML surrogates of the mechanistic twin. Re-simulate with run_ai_designed_scenarios for exact mechanistic effects; calibrate before any real use._';
    txt = strjoin(L, newline);
    fid = fopen(outMd,'w'); if fid<0; return; end
    fwrite(fid, txt, 'char'); fclose(fid);
end

function s = localYN(b)
    if b; s = 'yes'; else; s = 'NO'; end
end
