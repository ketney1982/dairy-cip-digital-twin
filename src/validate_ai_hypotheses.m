% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function [resultsTbl, summary] = validate_ai_hypotheses(opts)
%VALIDATE_AI_HYPOTHESES  Deterministic statistical testing of AI hypotheses.
%
%   [RESULTSTBL, SUMMARY] = VALIDATE_AI_HYPOTHESES() reads results/ai_hypotheses.json
%   and tests each hypothesis on the synthetic dataset(s) using ONLY deterministic
%   statistics (Pearson correlation + simple/multiple linear regression). No
%   Gemini call is made here: this is the numeric check that the generative layer
%   is explicitly NOT trusted to perform.
%
%   Convention (set by gemini_hypothesis_generator): in variables_involved the
%   LAST entry is the OUTCOME and the FIRST is the PRIMARY predictor; any middle
%   entries are covariates included in a multiple regression.
%
%   Verdict per hypothesis (vs the stated expected_direction):
%       supported | partially_supported | not_supported | inconclusive
%
%   OPTS (all optional):
%       .hyp_path             results/ai_hypotheses.json
%       .dataset_csv          data/dairy_cip_synthetic_dataset.csv
%       .include_ai_designed  also pool data/dairy_cip_ai_designed_dataset.csv
%                             (default: true when that file exists)
%
%   Outputs:
%       results/ai_hypothesis_validation.csv
%       results/ai_hypothesis_validation_report.txt
%
%   >>> All inputs are SIMULATION-GENERATED SYNTHETIC DATA. A "supported" verdict
%   means the hypothesis holds IN THE SIMULATOR, NOT in a real plant. <<<
%
%   See also: GEMINI_HYPOTHESIS_GENERATOR, VALIDATE_OUTPUTS.

    if nargin < 1 || isempty(opts); opts = struct(); end
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(here);
    resDir  = fullfile(root,'results'); if ~exist(resDir,'dir'); mkdir(resDir); end

    hypPath = localOpt(opts,'hyp_path', fullfile(resDir,'ai_hypotheses.json'));
    csvPath = localOpt(opts,'dataset_csv', fullfile(root,'data','dairy_cip_synthetic_dataset.csv'));
    aiPath  = fullfile(root,'data','dairy_cip_ai_designed_dataset.csv');
    includeAI = localOpt(opts,'include_ai_designed', exist(aiPath,'file')==2);

    outCsv  = fullfile(resDir,'ai_hypothesis_validation.csv');
    outRep  = fullfile(resDir,'ai_hypothesis_validation_report.txt');

    if exist(hypPath,'file') ~= 2
        error('validate_ai_hypotheses:noHyp', ...
            ['Hypotheses file not found:\n  %s\n' ...
             'Run gemini_hypothesis_generator first.'], hypPath);
    end
    if exist(csvPath,'file') ~= 2
        error('validate_ai_hypotheses:noData','Dataset not found:\n  %s', csvPath);
    end

    % ---- Load hypotheses ------------------------------------------------
    doc = jsondecode(fileread(hypPath));
    if ~isfield(doc,'hypotheses') || isempty(doc.hypotheses)
        error('validate_ai_hypotheses:empty','No hypotheses in %s', hypPath);
    end
    H = doc.hypotheses;
    if iscell(H); H = [H{:}]; end

    % ---- Load + pool datasets (successful rows only) --------------------
    [D, srcNote, nSyn, nAI] = localLoadPool(csvPath, aiPath, includeAI);
    fprintf('[validate_ai_hypotheses] Testing %d hypotheses on %d rows (%s).\n', ...
        numel(H), height(D), srcNote);

    % ---- Test each hypothesis -------------------------------------------
    nH = numel(H);
    id        = strings(nH,1);  statement = strings(nH,1);
    primary   = strings(nH,1);  outcome   = strings(nH,1);  covars = strings(nH,1);
    expDir    = strings(nH,1);  testMethod= strings(nH,1);  sciVal = strings(nH,1);
    obsCorr   = nan(nH,1);      corrP     = nan(nH,1);       obsDir = strings(nH,1);
    regCoef   = nan(nH,1);      regCoefP  = nan(nH,1);       regR2  = nan(nH,1);
    nUsed     = nan(nH,1);      support   = strings(nH,1);   note   = strings(nH,1);

    for i = 1:nH
        h = H(i);
        id(i)         = string(localField(h,'id', sprintf('H%d',i)));
        statement(i)  = string(localField(h,'statement',''));
        expDir(i)     = string(lower(localField(h,'expected_direction','nonmonotonic')));
        testMethod(i) = string(localField(h,'test_method','correlation'));
        sciVal(i)     = string(localField(h,'scientific_value','medium'));

        vars = localVarList(h, D.Properties.VariableNames);
        if numel(vars) < 2
            support(i) = "inconclusive";
            note(i) = "Could not map >=2 dataset columns from variables_involved.";
            continue;
        end
        out  = vars{end};
        preds= vars(1:end-1);
        primary(i) = string(preds{1});
        outcome(i) = string(out);
        if numel(preds) > 1; covars(i) = string(strjoin(preds(2:end), '+')); end

        [r, p, n] = localCorr(D.(preds{1}), D.(out));
        obsCorr(i) = r; corrP(i) = p; nUsed(i) = n;
        obsDir(i)  = localSignWord(r);

        % Multiple/simple regression (partial effect of the primary predictor).
        [coef, coefP, rr2] = localRegress(D, preds, out);
        regCoef(i) = coef; regCoefP(i) = coefP; regR2(i) = rr2;

        [support(i), note(i)] = localVerdict(expDir(i), r, p, n);
    end

    resultsTbl = table(id, statement, primary, outcome, covars, expDir, testMethod, ...
        sciVal, obsCorr, corrP, obsDir, regCoef, regCoefP, regR2, nUsed, support, note, ...
        'VariableNames', {'id','statement','primary_predictor','outcome','covariates', ...
        'expected_direction','test_method','scientific_value','observed_corr','corr_p', ...
        'observed_direction','reg_primary_coef','reg_primary_p','reg_adj_R2','n_rows', ...
        'support','note'});

    writetable(resultsTbl, outCsv);

    % ---- Summary counts -------------------------------------------------
    summary = struct();
    summary.n_hypotheses        = nH;
    summary.n_supported         = sum(support=="supported");
    summary.n_partially         = sum(support=="partially_supported");
    summary.n_not_supported     = sum(support=="not_supported");
    summary.n_inconclusive      = sum(support=="inconclusive");
    summary.n_rows              = height(D);
    summary.source              = srcNote;
    summary.data_label          = 'simulation-generated synthetic data';

    % ---- Human-readable report ------------------------------------------
    localWriteReport(outRep, resultsTbl, summary, nSyn, nAI, includeAI);

    fprintf(['[validate_ai_hypotheses] supported=%d partial=%d not=%d inconclusive=%d ', ...
        '-> %s\n'], summary.n_supported, summary.n_partially, summary.n_not_supported, ...
        summary.n_inconclusive, outCsv);
end

% ======================================================================
function [D, srcNote, nSyn, nAI] = localLoadPool(csvPath, aiPath, includeAI)
% Pool successful rows from the synthetic dataset (+ optional AI-designed set).
    T = readtable(csvPath);
    if ismember('simulation_status', T.Properties.VariableNames)
        T = T(string(T.simulation_status)=="success",:);
    end
    nSyn = height(T); nAI = 0; D = T; srcNote = 'synthetic';
    if includeAI && exist(aiPath,'file')==2
        try
            A = readtable(aiPath);
            if ismember('simulation_status', A.Properties.VariableNames)
                A = A(string(A.simulation_status)=="success",:);
            end
            common = intersect(T.Properties.VariableNames, A.Properties.VariableNames, 'stable');
            % Keep only numeric-compatible common columns for vertical concat.
            D = [T(:,common); A(:,common)];
            nAI = height(A);
            srcNote = sprintf('synthetic + AI-designed (%d + %d rows)', nSyn, nAI);
        catch ME
            warning('validate_ai_hypotheses:aiPool','Could not pool AI-designed data: %s', ME.message);
            D = T; srcNote = 'synthetic (AI-designed pool failed)';
        end
    end
end

% ======================================================================
function vars = localVarList(h, colNames)
% Recognized dataset columns from variables_involved, preserving order.
    vars = {};
    raw = {};
    if isfield(h,'variables_involved') && ~isempty(h.variables_involved)
        x = h.variables_involved;
        if ischar(x); raw = {x};
        elseif isstring(x); raw = cellstr(x);
        elseif iscell(x); raw = cellfun(@(e) char(string(e)), x, 'UniformOutput', false);
        end
    end
    for i = 1:numel(raw)
        nm = strtrim(raw{i});
        if any(strcmp(colNames, nm)); vars{end+1} = nm; end %#ok<AGROW>
    end
end

% ======================================================================
function [r, p, n] = localCorr(x, y)
% Pearson correlation with p-value; manual fallback if corr() is unavailable.
    x = x(:); y = y(:);
    ok = ~ismissing(x) & ~ismissing(y) & isfinite(x) & isfinite(y);
    x = x(ok); y = y(ok); n = numel(x);
    r = NaN; p = NaN;
    if n < 3 || std(x)==0 || std(y)==0; return; end
    try
        [r, p] = corr(x, y);            % Statistics Toolbox
    catch
        c = cov(x,y); r = c(1,2)/(std(x)*std(y));   % manual fallback (no p-value)
        t = r * sqrt((n-2)/max(1-r^2, eps));
        p = NaN; %#ok<NASGU>
        p = 2 * (1 - localTcdf(abs(t), n-2));
    end
end

% ======================================================================
function [coef, coefP, adjR2] = localRegress(D, preds, out)
% Partial effect of the primary predictor via (multiple) linear regression.
    coef = NaN; coefP = NaN; adjR2 = NaN;
    try
        sub = D(:, [preds, {out}]);
        sub = rmmissing(sub);
        if height(sub) < numel(preds)+2; return; end
        lm = fitlm(sub, 'ResponseVar', out, 'PredictorVars', preds);
        % Primary predictor coefficient (row name == preds{1}).
        cn = lm.CoefficientNames;
        idx = find(strcmp(cn, preds{1}), 1);
        if ~isempty(idx)
            coef  = lm.Coefficients.Estimate(idx);
            coefP = lm.Coefficients.pValue(idx);
        end
        adjR2 = lm.Rsquared.Adjusted;
    catch
        % leave NaNs (graceful degradation)
    end
end

% ======================================================================
function [verdict, note] = localVerdict(expDir, r, p, n)
% Map expected direction + observed correlation to a support verdict.
    expDir = char(expDir);
    if ~isfinite(r) || n < 30
        verdict = "inconclusive";
        note = sprintf('Insufficient/degenerate data (n=%d, r=%.3f).', n, r);
        return;
    end
    signif = isfinite(p) && p < 0.05;
    ar = abs(r);
    if strcmp(expDir,'nonmonotonic')
        % Linear tests cannot confirm non-monotonicity; report linear strength.
        if ar < 0.10
            verdict = "inconclusive";
            note = sprintf('No strong linear trend (r=%.3f); non-monotonic claim needs a nonlinear test.', r);
        else
            verdict = "partially_supported";
            note = sprintf('A linear trend exists (r=%.3f); non-monotonic structure not separately tested.', r);
        end
        return;
    end
    expSign = 1; if strcmp(expDir,'negative'); expSign = -1; end
    obsSign = sign(r);
    if ar < 0.05
        verdict = "not_supported";
        note = sprintf('No detectable relationship (r=%.3f, p=%.3g); expected %s.', r, p, expDir);
    elseif obsSign == expSign
        if ar >= 0.10 && signif
            verdict = "supported";
        else
            verdict = "partially_supported";
        end
        note = sprintf('Observed %s relationship (r=%.3f, p=%.3g) matches expected %s.', ...
            char(localSignWord(r)), r, p, expDir);
    else
        if signif
            verdict = "not_supported";
        else
            verdict = "inconclusive";
        end
        note = sprintf('Observed %s relationship (r=%.3f, p=%.3g) contradicts expected %s.', ...
            char(localSignWord(r)), r, p, expDir);
    end
end

% ======================================================================
function w = localSignWord(r)
    if ~isfinite(r); w = "undefined";
    elseif r >= 0.05; w = "positive";
    elseif r <= -0.05; w = "negative";
    else; w = "negligible";
    end
end

% ======================================================================
function localWriteReport(outRep, T, summary, nSyn, nAI, includeAI)
    fid = fopen(outRep,'w');
    if fid < 0; error('validate_ai_hypotheses:fopen','Cannot write %s', outRep); end
    cu = onCleanup(@() fclose(fid));
    fprintf(fid,'================================================================\n');
    fprintf(fid,' DAIRY CIP DIGITAL TWIN - AI HYPOTHESIS VALIDATION REPORT\n');
    fprintf(fid,' (SIMULATION-GENERATED SYNTHETIC DATA - NOT real measurements)\n');
    fprintf(fid,' Deterministic statistics only; Gemini is NOT used in this step.\n');
    fprintf(fid,'================================================================\n\n');
    fprintf(fid,'Rows tested : %d  (synthetic=%d', summary.n_rows, nSyn);
    if includeAI; fprintf(fid,' + AI-designed=%d', nAI); end
    fprintf(fid,')\n');
    fprintf(fid,'Hypotheses  : %d\n', summary.n_hypotheses);
    fprintf(fid,'  supported           : %d\n', summary.n_supported);
    fprintf(fid,'  partially_supported : %d\n', summary.n_partially);
    fprintf(fid,'  not_supported       : %d\n', summary.n_not_supported);
    fprintf(fid,'  inconclusive        : %d\n\n', summary.n_inconclusive);
    for i = 1:height(T)
        fprintf(fid,'---- %s [%s] ----\n', T.id(i), upper(T.support(i)));
        fprintf(fid,'  Statement : %s\n', T.statement(i));
        fprintf(fid,'  Test      : %s of %s -> %s (expected %s)\n', T.test_method(i), ...
            T.primary_predictor(i), T.outcome(i), T.expected_direction(i));
        if strlength(T.covariates(i))>0
            fprintf(fid,'  Covariates: %s\n', T.covariates(i));
        end
        fprintf(fid,'  Pearson r : %.3f (p=%.3g, n=%d) -> observed %s\n', ...
            T.observed_corr(i), T.corr_p(i), T.n_rows(i), T.observed_direction(i));
        if isfinite(T.reg_adj_R2(i))
            fprintf(fid,'  Regression: primary coef=%.4g (p=%.3g), adj R^2=%.3f\n', ...
                T.reg_primary_coef(i), T.reg_primary_p(i), T.reg_adj_R2(i));
        end
        fprintf(fid,'  Verdict   : %s - %s\n\n', T.support(i), T.note(i));
    end
    fprintf(fid,'NOTE: "supported" means the relationship holds IN THE SIMULATOR.\n');
    fprintf(fid,'It is NOT evidence about a real dairy plant. Calibration with\n');
    fprintf(fid,'industrial data and microbiological validation remain required.\n');
end

% ======================================================================
function v = localOpt(opts, field, default)
    if isstruct(opts) && isfield(opts, field) && ~isempty(opts.(field))
        v = opts.(field);
    else
        v = default;
    end
end

function v = localField(s, f, default)
    v = default;
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f))
        try
            v = char(string(s.(f)));
        catch
            v = default;
        end
    end
end

% ======================================================================
function p = localTcdf(t, df)
% Minimal Student-t CDF via the regularized incomplete beta (fallback only).
    x = df / (df + t^2);
    ib = betainc(x, df/2, 0.5);
    p = 1 - 0.5*ib;
end
