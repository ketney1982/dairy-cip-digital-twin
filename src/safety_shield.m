% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function shield = safety_shield(recipe, opts)
%SAFETY_SHIELD  Deterministic safety gate for a single CIP recipe.
%
%   shield = SAFETY_SHIELD(recipe) checks ONE candidate CIP recipe against all
%   hard safety constraints and returns a verdict. This is the authoritative,
%   deterministic gate: NO AI/Gemini output may be presented as usable unless it
%   passes safety_shield. Gemini cannot bypass or override it.
%
%   recipe : struct (or 1-row table) with the decision variables
%            T_C, Q_m3h, t_pre, t_alk, t_int, t_final, NaOH_pct, heat_rec,
%            water_rec (soil0 optional; defaults to 0.5, the uncertainty cond.).
%
%   opts (all optional):
%       .policy / .policy_path    constraints (default selected_policy_config.json)
%       .uncertainty_path         models/uncertainty_surrogates.mat (preferred)
%       .point_path               results/surrogate_models.mat (fallback)
%       .metrics_csv              results/surrogate_metrics.csv  (R2 floor check)
%       .model_audit_path         results/model_audit_report.json (high-severity)
%       .max_total_uncertainty    advisory threshold on normalized interval width
%       .unc/.point/.metrics/.audit_high  pre-loaded handles (avoid re-loading)
%
%   VERDICT (struct):
%       .gate_passed   true only if NO hard constraint is violated
%       .research_only true if a global caveat applies (low surrogate R2,
%                      unresolved HIGH-severity model audit, or excess uncertainty)
%       .violations    cellstr of hard-constraint violations
%       .advisories    cellstr of research_only reasons
%       .predicted     per-target mean/lower/upper (conservative bounds used)
%       .basis         'uncertainty_conservative' | 'point_estimate'
%       .not_for_real_time_control = true ; .human_approval_required = true
%
%   Hard checks use CONSERVATIVE bounds when uncertainty surrogates exist:
%   cleaning q05 >= min_cleaning_score; COD/water/energy/CO2/hygienic q95 <= caps;
%   all inputs within P.lb/P.ub.
%
%   >>> SIMULATION-GENERATED SYNTHETIC surrogate predictions. Passing the shield
%   is NOT a real-world safety guarantee; it is a synthetic feasibility check. <<<
%
%   See also: AI_SUPERVISORY_CONTROL_RECOMMENDER, TRAIN_UNCERTAINTY_SURROGATES.

    if nargin < 2 || isempty(opts); opts = struct(); end
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(here);
    P = cip_parameters();
    resDir = fullfile(root,'results');

    % ---- Resolve recipe -> predictor vector -----------------------------
    x = localRecipeVector(recipe, P);

    % ---- Policy constraints --------------------------------------------
    con = localPolicy(opts, resDir, P);

    shield = struct();
    shield.mode = 'deterministic_safety_shield';
    shield.not_for_real_time_control = true;
    shield.human_approval_required = true;
    shield.data_label = 'simulation-generated synthetic data - synthetic feasibility check only';
    shield.recipe = localVecToStruct(x, P);
    shield.constraints_applied = con;
    violations = {}; advisories = {};

    % ---- (1) input bounds (hard) ---------------------------------------
    tol = 1e-6;
    for k = 1:numel(P.var_names)
        if x(k) < P.lb(k)-tol || x(k) > P.ub(k)+tol
            violations{end+1} = sprintf('%s=%.4g outside [%.4g, %.4g]', ...
                P.var_names{k}, x(k), P.lb(k), P.ub(k)); %#ok<AGROW>
        end
    end

    % ---- (2) predict metrics (conservative if uncertainty available) ----
    [pred, basis, totUnc] = localPredict(x, opts, root);
    shield.basis = basis;
    shield.predicted = pred;
    shield.total_uncertainty = totUnc;

    % ---- (3) hard environmental/hygiene caps (conservative bounds) ------
    if isfield(pred,'cleaning_score')
        if pred.cleaning_score.lower < con.min_cleaning_score
            violations{end+1} = sprintf('cleaning_score lower-bound %.2f < floor %.2f', ...
                pred.cleaning_score.lower, con.min_cleaning_score);
        end
    end
    violations = localCap(violations, pred, 'COD_mgL',          con.max_COD_mgL,          'mg/L');
    violations = localCap(violations, pred, 'water_L',          con.max_water_L,          'L');
    violations = localCap(violations, pred, 'total_energy_kWh', con.max_total_energy_kWh, 'kWh');
    violations = localCap(violations, pred, 'CO2eq_kg',         con.max_CO2eq_kg,         'kg');
    violations = localCap(violations, pred, 'hygienic_risk',    con.max_hygienic_risk,    '-');

    % ---- (4) global research_only caveats ------------------------------
    % Check the metrics that MATCH the prediction basis: when conservative
    % uncertainty bounds are used, judge the QUANTILE surrogates' R2/coverage
    % (uncertainty_surrogate_metrics.csv), not only the point surrogate R2.
    [lowR2, r2map, lowCov, metSrc] = localLowR2(opts, resDir, P, con, basis);
    if ~isempty(lowR2)
        advisories{end+1} = sprintf('Critical surrogate R^2 below %.2f (%s): %s', ...
            P.surrogate_r2_floor, metSrc, strjoin(lowR2, ', '));
    end
    if ~isempty(lowCov)
        advisories{end+1} = sprintf('Uncertainty interval coverage below 0.80 for: %s (intervals may be too narrow)', ...
            strjoin(lowCov, ', '));
    end
    nHigh = localAuditHigh(opts, resDir);
    if nHigh > 0
        advisories{end+1} = sprintf('Model audit has %d unresolved HIGH-severity flag(s)', nHigh);
    end
    maxUnc = localOpt(opts,'max_total_uncertainty', NaN);
    if isfinite(maxUnc) && isfinite(totUnc) && totUnc > maxUnc
        advisories{end+1} = sprintf('Total surrogate uncertainty %.3f exceeds threshold %.3f', totUnc, maxUnc);
    end

    % ---- Verdict --------------------------------------------------------
    shield.violations    = violations;
    shield.advisories    = advisories;
    shield.surrogate_R2  = r2map;
    shield.surrogate_metrics_source = metSrc;   % which metrics file the R2 came from
    shield.model_audit_high_severity = nHigh;
    shield.gate_passed   = isempty(violations);
    shield.research_only = ~isempty(advisories);
    shield.usable_for_research = shield.gate_passed;     % still requires human approval
    shield.note = ['Deterministic shield: AI/Gemini cannot bypass it. gate_passed ', ...
        'reflects hard constraints; research_only reflects global caveats. Human ', ...
        'approval mandatory; not for real-time control.'];
end

% ======================================================================
function x = localRecipeVector(recipe, P)
    x = nan(1, numel(P.var_names));
    if istable(recipe); recipe = table2struct(recipe(1,:)); end
    if ~isstruct(recipe)
        error('safety_shield:badRecipe','recipe must be a struct or 1-row table.');
    end
    for k = 1:numel(P.var_names)
        nm = P.var_names{k};
        if isfield(recipe, nm) && isscalar(recipe.(nm)) && isnumeric(recipe.(nm))
            x(k) = double(recipe.(nm));
        elseif strcmp(nm,'soil0')
            x(k) = 0.5;                       % fixed uncertainty condition default
        else
            error('safety_shield:missingVar','recipe is missing required variable "%s".', nm);
        end
    end
end

function s = localVecToStruct(x, P)
    s = struct();
    for k = 1:numel(P.var_names); s.(P.var_names{k}) = round(x(k),4); end
end

% ======================================================================
function con = localPolicy(opts, resDir, P)
    con = struct('min_cleaning_score',max(95,P.min_cleaning_score), ...
        'max_COD_mgL',NaN,'max_hygienic_risk',NaN,'max_water_L',NaN, ...
        'max_total_energy_kWh',NaN,'max_CO2eq_kg',NaN);
    cfg = [];
    if isfield(opts,'policy') && isstruct(opts.policy)
        cfg = opts.policy;
    else
        pth = localOpt(opts,'policy_path', fullfile(resDir,'selected_policy_config.json'));
        if exist(pth,'file')==2
            try
                cfg = jsondecode(fileread(pth));
            catch
                cfg = [];
            end
        end
    end
    if isstruct(cfg) && isfield(cfg,'constraints')
        con.min_cleaning_score = max(95, localScalar(cfg.constraints,'min_cleaning_score', con.min_cleaning_score));
        for f = {'max_COD_mgL','max_hygienic_risk','max_water_L','max_total_energy_kWh','max_CO2eq_kg'}
            v = localScalar(cfg.constraints, f{1}, NaN);
            if isfinite(v) && v > 0; con.(f{1}) = v; end
        end
    end
end

% ======================================================================
function [pred, basis, totUnc] = localPredict(x, opts, root)
    pred = struct(); basis = 'none'; totUnc = NaN;
    tgts = {'cleaning_score','COD_mgL','water_L','total_energy_kWh','CO2eq_kg','hygienic_risk'};

    % Preferred: conservative bounds from quantile regression forests.
    unc = localOpt(opts,'unc', []);
    if isempty(unc)
        up = localOpt(opts,'uncertainty_path', fullfile(root,'models','uncertainty_surrogates.mat'));
        if exist(up,'file')==2
            try
                unc = load(up);
            catch
                unc = [];
            end
        end
    end
    if ~isempty(unc) && isfield(unc,'qrf')
        q = unc.quantiles; iLo=find(abs(q-0.05)<1e-9,1); iMd=find(abs(q-0.5)<1e-9,1); iHi=find(abs(q-0.95)<1e-9,1);
        if isempty(iLo); iLo=1; end; if isempty(iMd); iMd=2; end; if isempty(iHi); iHi=numel(q); end
        widths = [];
        ok = true;
        for i = 1:numel(tgts)
            t = tgts{i};
            if ~isfield(unc.qrf, t); ok = false; break; end
            qq = quantilePredict(unc.qrf.(t), x, 'Quantile', q);
            lo = qq(iLo); md = qq(iMd); hi = qq(iHi);
            [lo,md,hi] = localClampTarget(t, lo, md, hi);
            pred.(t) = struct('mean',round(md,4),'lower',round(lo,4),'upper',round(hi,4));
            widths(end+1) = max(hi-lo,0); %#ok<AGROW>
        end
        if ok
            basis = 'uncertainty_conservative';
            % normalize widths by target scale for a 0..1-ish aggregate
            scales = [100, 5000, 2700, 130, 26, 1];   % rough target ranges
            totUnc = round(mean(widths(:).' ./ scales),4);
            return;
        end
    end

    % Fallback: point surrogates (mean=lower=upper; no interval).
    pp = localOpt(opts,'point', []);
    if isempty(pp)
        pth = localOpt(opts,'point_path', fullfile(root,'results','surrogate_models.mat'));
        if exist(pth,'file')==2
            try
                pp = load(pth);
            catch
                pp = [];
            end
        end
    end
    if ~isempty(pp) && isfield(pp,'models')
        Tb = array2table(x, 'VariableNames', pp.predictors);
        for i = 1:numel(tgts)
            t = tgts{i};
            if isfield(pp.models, t)
                v = predict(pp.models.(t), Tb);
                [vc,~,~] = localClampTarget(t, v, v, v);   % clamp the point estimate
                pred.(t) = struct('mean',round(vc,4),'lower',round(vc,4),'upper',round(vc,4));
            end
        end
        basis = 'point_estimate';
        totUnc = 0;   % no interval available
    end
end

function [lo,md,hi] = localClampTarget(t, lo, md, hi)
    if strcmp(t,'cleaning_score')
        lo=min(100,max(0,lo)); md=min(100,max(0,md)); hi=min(100,max(0,hi));
    elseif strcmp(t,'hygienic_risk')
        lo=min(1,max(0,lo)); md=min(1,max(0,md)); hi=min(1,max(0,hi));
    else
        lo=max(0,lo); md=max(0,md); hi=max(0,hi);
    end
end

% ======================================================================
function v = localCap(v, pred, name, cap, unit)
    if isfinite(cap) && isfield(pred, name)
        ub = pred.(name).upper;          % conservative upper bound
        if isfinite(ub) && ub > cap
            v{end+1} = sprintf('%s upper-bound %.4g > cap %.4g %s', name, ub, cap, unit);
        end
    end
end

% ======================================================================
function [lowR2, r2map, lowCov, metSrc] = localLowR2(opts, resDir, P, con, basis)
% Judge surrogate reliability against the metrics file that MATCHES the
% prediction basis. For uncertainty_conservative bounds, use the quantile-forest
% metrics (R2 + 90% coverage); otherwise the point-surrogate metrics.
    if nargin < 5; basis = 'point_estimate'; end
    r2map = struct(); lowR2 = {}; lowCov = {};
    crit = P.critical_targets;
    if isfield(con,'max_hygienic_risk') && isfinite(con.max_hygienic_risk) && ~ismember('hygienic_risk',crit)
        crit = [crit, {'hygienic_risk'}];
    end
    if strcmp(basis,'uncertainty_conservative')
        mp = localOpt(opts,'uncertainty_metrics_csv', fullfile(resDir,'uncertainty_surrogate_metrics.csv'));
        metSrc = 'uncertainty_surrogate_metrics';
    else
        mp = localOpt(opts,'metrics_csv', fullfile(resDir,'surrogate_metrics.csv'));
        metSrc = 'surrogate_metrics';
    end
    M = [];
    if exist(mp,'file')==2
        try
            M = readtable(mp, 'VariableNamingRule','preserve');
        catch
            M = [];
        end
    end
    if isempty(M); lowR2 = crit; return; end       % no metrics => treat all critical as unverified
    hasCov = ismember('coverage_90', M.Properties.VariableNames);
    for i = 1:numel(crit)
        idx = find(strcmp(string(M.target), crit{i}),1);
        if isempty(idx)
            lowR2{end+1} = crit{i}; %#ok<AGROW>
        else
            r2 = M.R2(idx); r2map.(crit{i}) = round(r2,4);
            if ~(isfinite(r2) && r2 >= P.surrogate_r2_floor); lowR2{end+1} = crit{i}; end %#ok<AGROW>
            if hasCov
                cov = M.coverage_90(idx);
                if isfinite(cov) && cov < 0.80; lowCov{end+1} = crit{i}; end %#ok<AGROW>
            end
        end
    end
end

% ======================================================================
function n = localAuditHigh(opts, resDir)
    n = localOpt(opts,'audit_high', NaN);
    if isfinite(n); return; end
    n = 0;
    pth = localOpt(opts,'model_audit_path', fullfile(resDir,'model_audit_report.json'));
    if exist(pth,'file')==2
        try
            A = jsondecode(fileread(pth));
            if isfield(A,'n_high_severity'); n = A.n_high_severity;
            elseif isfield(A,'model_audit_flags')
                F = A.model_audit_flags; if iscell(F); F=[F{:}]; end
                n = sum(arrayfun(@(f) isfield(f,'severity') && strcmpi(char(string(f.severity)),'high'), F));
            end
        catch
            n = 0;
        end
    end
end

% ======================================================================
function v = localScalar(s, field, default)
    v = default;
    if isstruct(s) && isfield(s, field)
        x = s.(field);
        if isnumeric(x) && isscalar(x); v = x;
        elseif isnumeric(x) && ~isempty(x); v = x(1); end
    end
end

function v = localOpt(opts, field, default)
    if isstruct(opts) && isfield(opts, field) && ~isempty(opts.(field))
        v = opts.(field);
    else
        v = default;
    end
end
