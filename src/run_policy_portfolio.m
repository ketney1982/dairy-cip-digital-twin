% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% RUN_POLICY_PORTFOLIO  Context-dependent CIP recommendations across profiles.
%
%   For each canonical operational profile (cip_policy_profiles) this driver
%   selects a recommended CIP recipe from the SAME surrogate "achievable
%   envelope", applying that profile's constraints (caps) and objective weights.
%   The point is practical value: the same plant receives DIFFERENT recommended
%   recipes depending on the managerial / regulatory context (water scarcity,
%   energy price spike, COD discharge limit, carbon target, hygiene priority,
%   balanced default).
%
%   Method (deterministic, fast, self-contained): one large uniform sample over
%   the 9 operator-controllable variables (soil0 fixed as an uncertainty
%   condition, matching optimize_cip_pareto) is evaluated with the trained
%   surrogates to form the feasible envelope (cleaning_score >= 95). Each profile
%   then (a) filters the envelope by its caps and (b) picks the recipe minimizing
%   its weighted, normalized objective - a constrained weighted-sum scalarization
%   over the same surrogate pipeline. No Gemini is used here; selection is purely
%   numeric.
%
%   Outputs:
%     results/policy_portfolio_results.csv
%     results/policy_portfolio_report.txt
%     figures/fig_policy_portfolio_tradeoffs.png only when
%     CIP_MATLAB_FIGURES=true (Python manuscript figures use the CSV by default)
%
%   >>> All values are SIMULATION-GENERATED SYNTHETIC surrogate predictions. <<<
%
%   See also: CIP_POLICY_PROFILES, OPTIMIZE_CIP_PARETO, GEMINI_POLICY_TRANSLATOR.

here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here);
P = cip_parameters();

resDir = fullfile(root,'results'); if ~exist(resDir,'dir'); mkdir(resDir); end
figDir = fullfile(root,'figures'); if ~exist(figDir,'dir'); mkdir(figDir); end
matPath = fullfile(resDir,'surrogate_models.mat');
outCsv  = fullfile(resDir,'policy_portfolio_results.csv');
outRep  = fullfile(resDir,'policy_portfolio_report.txt');
outFig  = fullfile(figDir,'fig_policy_portfolio_tradeoffs.png');

if exist(matPath,'file') ~= 2
    error('run_policy_portfolio:noModels', ...
        'Surrogate models not found:\n  %s\nRun train_surrogate_models first.', matPath);
end
S = load(matPath);
models = S.models; predictors = S.predictors;
reqT = {'water_L','total_energy_kWh','COD_mgL','CO2eq_kg','cleaning_score','EHPI'};
for k = 1:numel(reqT)
    if ~isfield(models, reqT{k})
        error('run_policy_portfolio:missingModel','Surrogate for %s is missing.', reqT{k});
    end
end
hasHyg = isfield(models,'hygienic_risk');

%% ----- Build the achievable envelope (one shared sample) --------------------
rng(42);
M = 30000;
soilIdx = find(strcmp(P.var_names,'soil0'),1);
soil0_fixed = 0.5;                                   % uncertainty condition (fixed)
lb = P.lb; ub = P.ub;
X = lb + rand(M, numel(lb)) .* (ub - lb);
X(:,soilIdx) = soil0_fixed;
Tx = array2table(X, 'VariableNames', predictors);

pr = struct();
pr.water_L          = max(0, predict(models.water_L, Tx));
pr.total_energy_kWh = max(0, predict(models.total_energy_kWh, Tx));
pr.COD_mgL          = max(0, predict(models.COD_mgL, Tx));
pr.CO2eq_kg         = max(0, predict(models.CO2eq_kg, Tx));
pr.cleaning_score   = min(100, max(0, predict(models.cleaning_score, Tx)));
pr.EHPI             = max(0, predict(models.EHPI, Tx));
if hasHyg
    pr.hygienic_risk = min(1, max(0, predict(models.hygienic_risk, Tx)));
else
    pr.hygienic_risk = nan(M,1);
end

% Global hygiene floor: the plant's achievable, hygienic envelope.
feas0 = pr.cleaning_score >= 95;
fprintf('[run_policy_portfolio] Envelope: %d/%d samples meet the 95%% hygiene floor.\n', sum(feas0), M);

%% ----- Per-profile constrained selection ------------------------------------
profiles = cip_policy_profiles();
nP = numel(profiles);
rows = {};
sel = struct([]);   % collected selected recipes for the figure
for p = 1:nP
    prof = profiles(p);
    con  = prof.constraints;
    w    = prof.objective_weights;

    feas = feas0 & (pr.cleaning_score >= con.min_cleaning_score);
    activeCaps = {sprintf('min_cleaning_score>=%.0f', con.min_cleaning_score)};
    [feas, activeCaps] = localApplyCap(feas, pr.COD_mgL,          con.max_COD_mgL,          'max_COD_mgL', activeCaps);
    [feas, activeCaps] = localApplyCap(feas, pr.water_L,          con.max_water_L,          'max_water_L', activeCaps);
    [feas, activeCaps] = localApplyCap(feas, pr.total_energy_kWh, con.max_total_energy_kWh, 'max_total_energy_kWh', activeCaps);
    [feas, activeCaps] = localApplyCap(feas, pr.CO2eq_kg,         con.max_CO2eq_kg,         'max_CO2eq_kg', activeCaps);
    if hasHyg
        [feas, activeCaps] = localApplyCap(feas, pr.hygienic_risk, con.max_hygienic_risk, 'max_hygienic_risk', activeCaps);
    end

    nFeas = sum(feas);
    rec = struct('profile',prof.profile,'policy_name',prof.policy_name, ...
        'risk_tolerance',prof.risk_tolerance,'n_feasible',nFeas, ...
        'active_caps',{activeCaps});

    if nFeas == 0
        rec.feasible = false;
        rec.note = 'No recipe in the envelope satisfies this profile''s caps.';
        for f = reqT; rec.(f{1}) = NaN; end
        rec.hygienic_risk = NaN;
        for v = P.operational_vars; rec.(v{1}) = NaN; end
        rec.soil0 = soil0_fixed;
    else
        idxF = find(feas);
        % weighted normalized selection over the feasible subset
        nW = localNorm(pr.water_L(idxF));
        nE = localNorm(pr.total_energy_kWh(idxF));
        nC = localNorm(pr.COD_mgL(idxF));
        n2 = localNorm(pr.CO2eq_kg(idxF));
        cC = 1 - localNorm(pr.cleaning_score(idxF));
        wv = [w.water_L, w.total_energy_kWh, w.COD_mgL, w.CO2eq_kg, w.cleaning_score];
        wv = wv / max(sum(wv), eps);
        score = wv(1)*nW + wv(2)*nE + wv(3)*nC + wv(4)*n2 + wv(5)*cC;
        [~,jj] = min(score);
        gi = idxF(jj);

        rec.feasible = true; rec.note = '';
        rec.water_L = round(pr.water_L(gi),3);
        rec.total_energy_kWh = round(pr.total_energy_kWh(gi),3);
        rec.COD_mgL = round(pr.COD_mgL(gi),3);
        rec.CO2eq_kg = round(pr.CO2eq_kg(gi),3);
        rec.cleaning_score = round(pr.cleaning_score(gi),3);
        rec.EHPI = round(pr.EHPI(gi),3);
        if hasHyg; rec.hygienic_risk = round(pr.hygienic_risk(gi),4); else; rec.hygienic_risk = NaN; end
        for v = P.operational_vars; rec.(v{1}) = round(X(gi, strcmp(P.var_names,v{1})),4); end
        rec.soil0 = soil0_fixed;
    end
    rows{end+1} = rec; %#ok<SAGROW>
    if isempty(sel); sel = rec; else; sel(end+1) = rec; end %#ok<SAGROW>
    fprintf('  %-20s feasible=%d/%d  cleaning=%.2f COD=%.0f water=%.0f energy=%.2f CO2=%.2f\n', ...
        prof.profile, nFeas, sum(feas0), localNan(rec,'cleaning_score'), localNan(rec,'COD_mgL'), ...
        localNan(rec,'water_L'), localNan(rec,'total_energy_kWh'), localNan(rec,'CO2eq_kg'));
end

%% ----- Save results table ---------------------------------------------------
T = localRowsToTable(rows, P);

% Min-max performance scores (0-100) for the Fig 8 heatmap, computed here so the
% Python plot reads them rather than recomputing the normalisation.
Sscore = cip_policy_scores(T);
for vv = Sscore.Properties.VariableNames
    T.(vv{1}) = Sscore.(vv{1});
end

writetable(T, outCsv);
fprintf('[run_policy_portfolio] Saved -> %s\n', outCsv);

%% ----- Report ---------------------------------------------------------------
localWriteReport(outRep, sel, hasHyg);

%% ----- Figure ---------------------------------------------------------------
if localEnvBool('CIP_MATLAB_FIGURES', false)
    localPortfolioFig(sel, outFig);
else
    fprintf('[run_policy_portfolio] Skipped MATLAB figure (Python manuscript figures use policy_portfolio_results.csv).\n');
end

fprintf('[run_policy_portfolio] Done. profiles=%d -> %s , %s , %s\n', nP, outCsv, outRep, outFig);

%% ===== Local functions ======================================================
function [feas, caps] = localApplyCap(feas, vals, cap, name, caps)
% Apply a finite environmental/hygienic cap to the feasibility mask.
    if isfinite(cap)
        feas = feas & (vals <= cap);
        caps{end+1} = sprintf('%s<=%.4g', name, cap);
    end
end

function y = localNorm(x)
    x = x(:); lo = min(x); hi = max(x);
    if hi - lo <= eps; y = zeros(size(x)); else; y = (x - lo)/(hi - lo); end
end

function v = localNan(rec, f)
    if isfield(rec,f) && ~isempty(rec.(f)); v = rec.(f); else; v = NaN; end
end

function T = localRowsToTable(rows, P)
    n = numel(rows);
    profile = strings(n,1); policy_name = strings(n,1); risk = strings(n,1);
    nfeas = zeros(n,1); feasible = false(n,1); caps = strings(n,1); note = strings(n,1);
    mets = {'water_L','total_energy_kWh','COD_mgL','CO2eq_kg','cleaning_score','EHPI','hygienic_risk'};
    metData = nan(n, numel(mets));
    ops = [P.operational_vars, {'soil0'}];
    opData = nan(n, numel(ops));
    for i = 1:n
        r = rows{i};
        profile(i) = string(r.profile); policy_name(i) = string(r.policy_name);
        risk(i) = string(r.risk_tolerance); nfeas(i) = r.n_feasible;
        feasible(i) = r.feasible; note(i) = string(r.note);
        caps(i) = string(strjoin(r.active_caps, '; '));
        for k = 1:numel(mets); if isfield(r,mets{k}); metData(i,k) = r.(mets{k}); end; end
        for k = 1:numel(ops);  if isfield(r,ops{k});  opData(i,k)  = r.(ops{k});  end; end
    end
    T = table(profile, policy_name, risk, feasible, nfeas, ...
        'VariableNames', {'profile','policy_name','risk_tolerance','feasible','n_feasible'});
    for k = 1:numel(mets); T.(mets{k}) = metData(:,k); end
    for k = 1:numel(ops);  T.(ops{k})  = opData(:,k);  end
    T.active_caps = caps; T.note = note;
end

function localWriteReport(outRep, sel, hasHyg)
    fid = fopen(outRep,'w');
    if fid < 0; return; end
    cu = onCleanup(@() fclose(fid));
    fprintf(fid,'================================================================\n');
    fprintf(fid,' DAIRY CIP - POLICY PORTFOLIO (context-dependent recommendations)\n');
    fprintf(fid,' (SIMULATION-GENERATED SYNTHETIC DATA - surrogate predictions)\n');
    fprintf(fid,' Same plant envelope; different recommended recipe per context.\n');
    fprintf(fid,'================================================================\n\n');
    fprintf(fid,'%-20s %8s %8s %8s %8s %9s %8s\n', ...
        'profile','clean%','COD','water','energy','CO2eq','EHPI');
    for i = 1:numel(sel)
        r = sel(i);
        if r.feasible
            fprintf(fid,'%-20s %8.2f %8.0f %8.0f %8.2f %9.2f %8.1f\n', ...
                r.profile, r.cleaning_score, r.COD_mgL, r.water_L, r.total_energy_kWh, r.CO2eq_kg, r.EHPI);
        else
            fprintf(fid,'%-20s   <no feasible recipe under this profile''s caps>\n', r.profile);
        end
    end
    fprintf(fid,'\n---- PER-PROFILE DETAIL ----\n');
    for i = 1:numel(sel)
        r = sel(i);
        fprintf(fid,'\n[%s] %s (risk: %s)\n', r.profile, r.policy_name, r.risk_tolerance);
        fprintf(fid,'  feasible recipes in envelope: %d\n', r.n_feasible);
        fprintf(fid,'  active caps: %s\n', strjoin(r.active_caps, '; '));
        if r.feasible
            fprintf(fid,'  recipe: T_C=%.1f Q=%.2f t_pre=%.0f t_alk=%.0f t_int=%.0f t_final=%.0f NaOH=%.2f heat_rec=%.2f water_rec=%.2f (soil0=%.2f fixed)\n', ...
                r.T_C, r.Q_m3h, r.t_pre, r.t_alk, r.t_int, r.t_final, r.NaOH_pct, r.heat_rec, r.water_rec, r.soil0);
            if hasHyg; fprintf(fid,'  predicted hygienic_risk: %.4f\n', r.hygienic_risk); end
        else
            fprintf(fid,'  %s\n', r.note);
        end
    end
    fprintf(fid,'\nNOTE: synthetic surrogate predictions; human approval and calibration\n');
    fprintf(fid,'required before any operational interpretation.\n');
end

function localPortfolioFig(sel, outFig)
    feasMask = arrayfun(@(r) r.feasible, sel);
    names = arrayfun(@(r) string(r.profile), sel);
    getm = @(f) arrayfun(@(r) localNan(r,f), sel);
    try
        f = figure('Visible','off','Position',[100 100 1200 800]);
        tl = tiledlayout(f,2,2,'Padding','compact','TileSpacing','compact');
        title(tl,'Policy portfolio: recommended recipe per context (SYNTHETIC surrogate predictions)');
        localBar(getm('water_L'),          names, feasMask, 'Water use (L)');
        localBar(getm('total_energy_kWh'), names, feasMask, 'Total energy (kWh)');
        localBar(getm('COD_mgL'),          names, feasMask, 'COD (mg/L)');
        localBar(getm('cleaning_score'),   names, feasMask, 'Cleaning score (%)');
        exportgraphics(f, outFig, 'Resolution',200);
        close(f);
    catch ME
        warning('run_policy_portfolio:fig','Figure failed: %s', ME.message);
    end
end

function localBar(vals, names, feasMask, ylab)
    nexttile;
    vals = vals(:); vals(~feasMask) = NaN;
    bar(vals); grid on; box on;
    set(gca,'XTick',1:numel(names),'XTickLabel',names);
    xtickangle(30); ylabel(ylab);
    title(ylab);
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
