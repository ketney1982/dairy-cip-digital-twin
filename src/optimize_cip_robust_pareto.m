% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% OPTIMIZE_CIP_ROBUST_PARETO  Uncertainty-aware robust Pareto selection.
%
%   Companion to optimize_cip_pareto.m (which is left untouched). Instead of
%   optimizing the MEAN surrogate predictions, this driver uses the quantile
%   regression forests from train_uncertainty_surrogates.m to optimize over
%   CONSERVATIVE bounds, and it penalizes high-uncertainty recipes. The result is
%   a robust Pareto front that is safe under surrogate uncertainty.
%
%   Conservative safety logic (worst-case within the 90% interval):
%     * cleaning_score_lower_bound (q05) must be >= min_cleaning_score
%     * COD_upper_bound (q95)            must be <= max_COD_mgL      (if finite)
%     * hygienic_risk_upper_bound (q95)  must be <= max_hygienic_risk (if finite)
%   Robust objectives (minimized): water q95, energy q95, COD q95, CO2 q95 and
%   -(cleaning q05). A robust score adds an uncertainty penalty so that, among
%   similar recipes, the one with TIGHTER intervals is preferred.
%
%   >>> All values are SIMULATION-GENERATED SYNTHETIC surrogate predictions.
%   The intervals are surrogate uncertainty, not measurement uncertainty. <<<
%
%   Output: results/robust_pareto_solutions.csv
%
%   See also: TRAIN_UNCERTAINTY_SURROGATES, OPTIMIZE_CIP_PARETO, SAFETY_SHIELD.

%% ----- Paths and models -----------------------------------------------------
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here);
P = cip_parameters();
resDir = fullfile(root,'results'); if ~exist(resDir,'dir'); mkdir(resDir); end
uncPath = fullfile(root,'models','uncertainty_surrogates.mat');
outCsv  = fullfile(resDir,'robust_pareto_solutions.csv');

if exist(uncPath,'file') ~= 2
    error('optimize_cip_robust_pareto:noModels', ...
        ['Uncertainty surrogates not found:\n  %s\n' ...
         'Run train_uncertainty_surrogates first.'], uncPath);
end
S = load(uncPath);
qrf = S.qrf; predictors = S.predictors; quantiles = S.quantiles;
reqT = {'cleaning_score','COD_mgL','water_L','total_energy_kWh','CO2eq_kg','hygienic_risk'};
for k = 1:numel(reqT)
    if ~isfield(qrf, reqT{k})
        error('optimize_cip_robust_pareto:missing','Uncertainty surrogate for %s is missing.', reqT{k});
    end
end
iLo = find(abs(quantiles-0.05)<1e-9,1); if isempty(iLo); iLo=1; end
iMd = find(abs(quantiles-0.50)<1e-9,1); if isempty(iMd); iMd=2; end
iHi = find(abs(quantiles-0.95)<1e-9,1); if isempty(iHi); iHi=numel(quantiles); end

%% ----- Policy-derived conservative constraints / weights --------------------
min_cleaning = max(95, P.min_cleaning_score);
max_COD = inf; max_hyg = inf;
wsel = struct('water_L',0.25,'total_energy_kWh',0.20,'COD_mgL',0.25, ...
              'CO2eq_kg',0.20,'cleaning_score',0.10);
policyPath = fullfile(resDir,'selected_policy_config.json');
if exist(policyPath,'file')==2
    try
        cfg = jsondecode(fileread(policyPath));
        if isfield(cfg,'constraints')
            mc = localScalar(cfg.constraints,'min_cleaning_score',min_cleaning);
            if isfinite(mc); min_cleaning = max(95,mc); end
            cd = localScalar(cfg.constraints,'max_COD_mgL',NaN);   if isfinite(cd)&&cd>0; max_COD = cd; end
            hg = localScalar(cfg.constraints,'max_hygienic_risk',NaN); if isfinite(hg)&&hg>0; max_hyg = hg; end
        end
        if isfield(cfg,'objective_weights')
            for f = fieldnames(wsel).'
                wv = localScalar(cfg.objective_weights, f{1}, NaN);
                if isfinite(wv); wsel.(f{1}) = wv; end
            end
        end
        fprintf('[optimize_cip_robust_pareto] Applied policy (%s).\n', policyPath);
    catch ME
        warning('optimize_cip_robust_pareto:policy','Policy read failed: %s', ME.message);
    end
end
lambda_unc = 0.5;   % uncertainty penalty weight in the robust score
fprintf('[optimize_cip_robust_pareto] Conservative: cleaning_lb>=%.1f, COD_ub<=%g, hyg_ub<=%g\n', ...
    min_cleaning, max_COD, max_hyg);

%% ----- Sample the operator decision space (soil0 fixed) --------------------
rng(42);
M = 5000;
soilIdx = find(strcmp(P.var_names,'soil0'),1);
X = P.lb + rand(M, numel(P.lb)) .* (P.ub - P.lb);
X(:,soilIdx) = 0.5;                          % fixed uncertainty condition

%% ----- Predict quantiles for each target -----------------------------------
lo = struct(); md = struct(); hi = struct(); wid = struct();
for k = 1:numel(reqT)
    tgt = reqT{k};
    q = quantilePredict(qrf.(tgt), X, 'Quantile', quantiles);   % M x nQuant
    lo.(tgt) = q(:,iLo); md.(tgt) = q(:,iMd); hi.(tgt) = q(:,iHi);
    wid.(tgt) = max(q(:,iHi) - q(:,iLo), 0);
end
% Clamp physical ranges.
for tgt = {'COD_mgL','water_L','total_energy_kWh','CO2eq_kg','hygienic_risk'}
    lo.(tgt{1}) = max(0, lo.(tgt{1})); md.(tgt{1}) = max(0, md.(tgt{1})); hi.(tgt{1}) = max(0, hi.(tgt{1}));
end
lo.cleaning_score = min(100, max(0, lo.cleaning_score));
md.cleaning_score = min(100, max(0, md.cleaning_score));
hi.cleaning_score = min(100, max(0, hi.cleaning_score));
hi.hygienic_risk  = min(1, hi.hygienic_risk);

%% ----- Conservative feasibility --------------------------------------------
feas = lo.cleaning_score >= min_cleaning;
if isfinite(max_COD); feas = feas & (hi.COD_mgL <= max_COD); end
if isfinite(max_hyg); feas = feas & (hi.hygienic_risk <= max_hyg); end
nFeas = sum(feas);
fprintf('[optimize_cip_robust_pareto] Conservatively feasible: %d / %d samples.\n', nFeas, M);
if nFeas == 0
    error('optimize_cip_robust_pareto:infeasible', ...
        'No conservatively-feasible recipe; relax the policy or retrain surrogates.');
end

idxF = find(feas);
% Robust (conservative) objectives to MINIMIZE.
F = [hi.water_L(idxF), hi.total_energy_kWh(idxF), hi.COD_mgL(idxF), ...
     hi.CO2eq_kg(idxF), -lo.cleaning_score(idxF)];

%% ----- Non-dominated (robust) front + robust score -------------------------
nd = localParetoFilter(F);
ndIdx = idxF(nd);

% Total normalized uncertainty over the feasible set (penalty).
uncTargets = reqT;
normWidth = zeros(numel(idxF), numel(uncTargets));
for k = 1:numel(uncTargets)
    w = wid.(uncTargets{k})(idxF);
    normWidth(:,k) = localNorm(w);
end
totUnc = mean(normWidth, 2);                       % 0..1, higher = more uncertain

% Robust score over the feasible set (lower = better): weighted conservative
% objectives + uncertainty penalty (cleaning uses its conservative lower bound).
nW = localNorm(hi.water_L(idxF));
nE = localNorm(hi.total_energy_kWh(idxF));
nC = localNorm(hi.COD_mgL(idxF));
n2 = localNorm(hi.CO2eq_kg(idxF));
cC = 1 - localNorm(lo.cleaning_score(idxF));
wv = [wsel.water_L, wsel.total_energy_kWh, wsel.COD_mgL, wsel.CO2eq_kg, wsel.cleaning_score];
wv = wv / max(sum(wv), eps);
robustScore = wv(1)*nW + wv(2)*nE + wv(3)*nC + wv(4)*n2 + wv(5)*cC + lambda_unc*totUnc;

%% ----- Assemble table (robust front only) ----------------------------------
keep = nd;                                  % logical over idxF -> the robust front
sub  = idxF(keep);
T = array2table(X(sub,:), 'VariableNames', P.var_names);
for k = 1:numel(reqT)
    tgt = reqT{k};
    T.([tgt '_mean'])  = round(md.(tgt)(sub),4);
    T.([tgt '_lower']) = round(lo.(tgt)(sub),4);
    T.([tgt '_upper']) = round(hi.(tgt)(sub),4);
    T.([tgt '_width']) = round(wid.(tgt)(sub),4);
end
T.total_uncertainty = round(totUnc(keep),4);
T.robust_score      = round(robustScore(keep),6);

% Selection labels on the robust front.
lab = strings(height(T),1); lab(:) = "";
[~,iB] = min(T.robust_score);                 lab(iB) = localAppend(lab(iB),"robust_balanced");
[~,iW] = min(T.water_L_upper);                lab(iW) = localAppend(lab(iW),"robust_lowest_water");
[~,iC] = min(T.COD_mgL_upper);                lab(iC) = localAppend(lab(iC),"robust_lowest_COD");
[~,iCl]= max(T.cleaning_score_lower);         lab(iCl)= localAppend(lab(iCl),"robust_highest_cleaning_lb");
[~,iU] = min(T.total_uncertainty);            lab(iU) = localAppend(lab(iU),"robust_lowest_uncertainty");
T.selection_label = cellstr(lab);

T.data_label = repmat({'simulation-generated synthetic data - robust (conservative) surrogate bounds'}, height(T),1);
writetable(T, outCsv);
fprintf('[optimize_cip_robust_pareto] Robust front = %d solutions -> %s\n', height(T), outCsv);
fprintf('[optimize_cip_robust_pareto] Balanced robust row = %d (label set).\n', iB);

%% ===== Local functions ======================================================
function nd = localParetoFilter(F)
%LOCALPARETOFILTER Non-dominated set (archive method); arch preallocated (no AGROW).
    n = size(F,1); nd = false(n,1);
    arch = zeros(1,n); na = 0;                 % preallocated archive + live count
    for ii = 1:n
        fi = F(ii,:);
        if na == 0; na = 1; arch(1) = ii; continue; end
        idx = arch(1:na);
        FA = F(idx,:);
        le = FA <= fi; lt = FA < fi;
        if any(all(le,2) & any(lt,2)); continue; end
        ge = FA >= fi; gt = FA > fi;
        keep = ~(all(ge,2) & any(gt,2));
        nk = sum(keep);
        arch(1:nk) = idx(keep);
        na = nk + 1; arch(na) = ii;
    end
    nd(arch(1:na)) = true;
end

function y = localNorm(x)
    x = x(:); loo = min(x); hii = max(x);
    if hii - loo <= eps; y = zeros(size(x)); else; y = (x - loo)/(hii - loo); end
end

function v = localScalar(s, field, default)
    v = default;
    if isstruct(s) && isfield(s, field)
        x = s.(field);
        if isnumeric(x) && isscalar(x); v = x;
        elseif isnumeric(x) && ~isempty(x); v = x(1); end
    end
end

function s = localAppend(s, lab)
    if strlength(s)==0; s = lab; else; s = s + "+" + lab; end
end
