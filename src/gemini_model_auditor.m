% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function audit = gemini_model_auditor()
%GEMINI_MODEL_AUDITOR  AI-assisted audit of the model's structure & plausibility.
%
%   audit = GEMINI_MODEL_AUDITOR() sends the model equation summary
%   (results/model_equation_summary.json), the dataset summary
%   (results/dataset_summary.json) and the prior plausibility audit
%   (results/plausibility_audit.json, if present) to Gemini and asks it to flag
%   structural / physical concerns in the mechanistic model FOR HUMAN REVIEW.
%
%   GOVERNANCE:
%   * Gemini does NOT validate the model as correct and is NOT ground truth.
%   * NO parameter or equation is modified by this function (read-only audit).
%   * Output is sanitized locally. If Gemini is unavailable or returns invalid
%     JSON, a deterministic MOCK audit is derived from the equation summary's
%     review-flagged relations and the dataset correlations, and clearly labelled.
%   * All inputs describe SIMULATION-GENERATED SYNTHETIC data.
%
%   Strict JSON output (results/model_audit_report.json):
%     {"model_audit_flags":[{"severity","model_component","issue",
%        "evidence_from_summary","recommended_human_review","suggested_experiment"}],
%      "calibration_priorities":[...],"minimum_real_measurements_needed":[...],
%      "manuscript_limitations_text":"..."}
%
%   See also: BUILD_MODEL_EQUATION_SUMMARY, GEMINI_PLAUSIBILITY_AUDITOR.

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(here);
    resDir = fullfile(root,'results'); if ~exist(resDir,'dir'); mkdir(resDir); end
    outPath = fullfile(resDir,'model_audit_report.json');

    eqPath  = fullfile(resDir,'model_equation_summary.json');
    sumPath = fullfile(resDir,'dataset_summary.json');
    audPath = fullfile(resDir,'plausibility_audit.json');

    % Ensure the equation summary exists (build it if necessary).
    if exist(eqPath,'file') ~= 2
        warning('gemini_model_auditor:noEq','model_equation_summary.json missing; building it.');
        build_model_equation_summary();
    end
    eqTxt  = localReadOrEmpty(eqPath);
    sumTxt = localReadOrEmpty(sumPath);
    audTxt = localReadOrEmpty(audPath);

    sys = strjoin({ ...
        'You are a cautious mechanistic-model auditor for a dairy CIP digital twin.', ...
        'You receive a TEXTUAL equation summary, dataset summary statistics, and a', ...
        'prior plausibility audit of a SYNTHETIC dataset.', ...
        'RULES:', ...
        '1. Do NOT validate the model as true; do NOT claim industrial validation.', ...
        '2. Use ONLY the provided material; do not invent data.', ...
        '3. Flag structural/physical concerns that need HUMAN review.', ...
        '4. Do NOT output new parameter values; suggest experiments/measurements instead.', ...
        '5. Return VALID JSON ONLY (no markdown), with this shape:', ...
        '{"model_audit_flags":[{"severity":"low|medium|high","model_component":"...",', ...
        '  "issue":"...","evidence_from_summary":"...","recommended_human_review":"...",', ...
        '  "suggested_experiment":"..."}],', ...
        ' "calibration_priorities":["..."],"minimum_real_measurements_needed":["..."],', ...
        ' "manuscript_limitations_text":"..."}'}, newline);

    usr = strjoin({ ...
        'MODEL EQUATION SUMMARY (JSON):', eqTxt, '', ...
        'DATASET SUMMARY (JSON):', sumTxt, '', ...
        'PRIOR PLAUSIBILITY AUDIT (JSON):', audTxt, '', ...
        'Pay special attention to relations marked NEEDS_REVIEW or KNOWN_SIMPLIFICATION', ...
        'in the equation summary, and to COD coupling (soil0 vs COD, NaOH vs COD).'}, newline);

    [txt, info] = gemini_call(sys, usr, struct('json_only',true,'temperature',0.2,'max_tokens',8192));

    usedMock = false; audit = struct();
    if info.ok
        try
            audit = jsondecode(localStripFences(txt));
        catch ME
            warning('gemini_model_auditor:parse','Bad JSON (%s); using MOCK.', ME.message);
            usedMock = true;
        end
    else
        usedMock = true;
        if ~strcmp(info.status,'mock_mode')   % deliberate mock is not a warning
            warning('gemini_model_auditor:noLLM','Gemini unavailable (%s); using MOCK.', info.status);
        end
    end

    if usedMock
        audit = localMockAudit(eqPath, sumPath, audPath);
    end

    audit = localNormalize(audit, usedMock);

    fid = fopen(outPath,'w');
    if fid < 0; error('gemini_model_auditor:fopen','Cannot write %s', outPath); end
    fwrite(fid, jsonencode(audit,'PrettyPrint',true), 'char'); fclose(fid);

    nHigh = sum(arrayfun(@(f) strcmpi(localGet(f,'severity',''),'high'), audit.model_audit_flags));
    tag = gemini_mode_tag(info, usedMock);
    fprintf('[gemini_model_auditor] (%s) %d flag(s), %d high-severity -> %s\n', ...
        tag, numel(audit.model_audit_flags), nHigh, outPath);
end

% ======================================================================
function audit = localMockAudit(eqPath, sumPath, audPath)
% Deterministic audit derived from the equation summary's flagged relations,
% the dataset correlations, and the prior plausibility audit.
    mkflag = @(sev,comp,iss,ev,rev,exp) struct('severity',sev,'model_component',comp, ...
        'issue',iss,'evidence_from_summary',ev,'recommended_human_review',rev, ...
        'suggested_experiment',exp);
    flags = {};

    % (a) Pull review-flagged relations from the equation summary.
    try
        eq = jsondecode(fileread(eqPath));
        if isfield(eq,'expected_relations')
            R = eq.expected_relations; if iscell(R); R = [R{:}]; end
            for i = 1:numel(R)
                st = localGet(R(i),'review_status','');
                if strcmpi(st,'NEEDS_REVIEW')
                    flags{end+1} = mkflag('high', ...
                        sprintf('%s -> %s', localGet(R(i),'driver','?'), localGet(R(i),'target','?')), ...
                        localGet(R(i),'rationale',''), ...
                        'Equation summary marks this relation NEEDS_REVIEW.', ...
                        'Re-derive the coupling from a mass balance with a domain expert.', ...
                        'AI-designed batch sweeping soil0 at fixed recipe to measure the soil0->COD slope.'); %#ok<AGROW>
                elseif strcmpi(st,'KNOWN_SIMPLIFICATION')
                    flags{end+1} = mkflag('medium', ...
                        sprintf('%s -> %s', localGet(R(i),'driver','?'), localGet(R(i),'target','?')), ...
                        localGet(R(i),'rationale',''), ...
                        'Equation summary marks this relation KNOWN_SIMPLIFICATION.', ...
                        'Decide whether the simplification is acceptable for the study scope.', ...
                        'Compare COD with/without the chemical-equivalent term across NaOH levels.'); %#ok<AGROW>
                end
            end
        end
    catch
        % equation summary unreadable; continue with dataset-based checks
    end

    % (b) Cross-check the dataset's soil0 vs COD correlation.
    try
        S = jsondecode(fileread(sumPath));
        if isfield(S,'key_correlations') && isfield(S.key_correlations,'soil0_vs_COD_mgL')
            soilCODcorr = S.key_correlations.soil0_vs_COD_mgL;
            if isfinite(soilCODcorr) && abs(soilCODcorr) < 0.05
                flags{end+1} = mkflag('high','COD effluent sub-model', ...
                    sprintf('Initial soil load barely affects COD (corr soil0,COD=%.3f ~ 0), contradicting organic-load chemistry.', soilCODcorr), ...
                    'dataset_summary.key_correlations.soil0_vs_COD_mgL ~ 0.', ...
                    'Confirm the organic-COD term tracks total soil removed, not just instantaneous rate.', ...
                    'Sweep soil0 over [0.1,1.0] at a fixed recipe; expect monotonically rising COD.');
            end
        end
    catch
        % summary unreadable; skip
    end

    % (c) Incorporate prior plausibility-audit high-severity flags.
    if exist(audPath,'file')==2
        try
            A = jsondecode(fileread(audPath));
            if isfield(A,'plausibility_flags')
                PF = A.plausibility_flags; if iscell(PF); PF = [PF{:}]; end
                for i = 1:numel(PF)
                    if strcmpi(localGet(PF(i),'severity',''),'high')
                        flags{end+1} = mkflag('high','flagged-by-plausibility-audit', ...
                            localGet(PF(i),'issue',''), ...
                            sprintf('Prior plausibility audit: %s', localGet(PF(i),'parameter_or_relationship','')), ...
                            localGet(PF(i),'recommended_human_check','Human review required.'), ...
                            'Targeted simulation isolating the flagged relationship.'); %#ok<AGROW>
                    end
                end
            end
        catch
            % audit unreadable; skip
        end
    end

    % (d) Always include the structural-proxy caveat.
    flags{end+1} = mkflag('medium','cleaning_score / hygienic_risk proxies', ...
        'cleaning_score and hygienic_risk are derived only from residual soil; they are not microbiological measurements.', ...
        'Equation summary: cleaning_score = clamp((1-soil)*100,0,100).', ...
        'Do not treat cleaning_score as food-safety verification.', ...
        'Correlate cleaning_score against ATP/microbial swabs in a future calibration campaign.');

    audit = struct();
    audit.model_audit_flags = [flags{:}];
    audit.calibration_priorities = { ...
        'Re-estimate soil-removal kinetics (k_cal and base rates) from plant/literature data.'; ...
        'Re-derive the effluent COD model so it tracks organic soil load (soil0).'; ...
        'Separate organic vs chemical contributions to COD with measured data.'};
    audit.minimum_real_measurements_needed = { ...
        'Time-resolved effluent COD per CIP phase.'; ...
        'Initial soil load (soil0) proxy and post-clean residual soil / ATP.'; ...
        'Inlet/outlet temperatures and thermal energy for heat-recovery validation.'; ...
        'Water flow and recovered-water fraction per phase.'};
    audit.manuscript_limitations_text = ['The mechanistic twin is an uncalibrated ', ...
        'proof of concept. Effluent COD_mgL is an ORGANIC-load proxy driven by soil ', ...
        'removal (so it tracks soil0); NaOH residual is reported separately as ', ...
        'NaOH_residual_mgL / COD_chem_equiv_mgL and is NOT folded into organic COD. ', ...
        'cleaning_score is a soil-based proxy rather than a microbiological ', ...
        'measurement. Results are simulation-generated synthetic data and require ', ...
        'calibration with industrial measurements and food-safety validation before ', ...
        'any operational interpretation.'];
end

% ======================================================================
function audit = localNormalize(audit, usedMock)
    validSev = {'low','medium','high'};
    % --- flags ---
    if ~isfield(audit,'model_audit_flags') || isempty(audit.model_audit_flags)
        audit.model_audit_flags = struct('severity','low','model_component','overall', ...
            'issue','No specific flags produced.','evidence_from_summary','', ...
            'recommended_human_review','General expert review still advised.', ...
            'suggested_experiment','');
    end
    F = audit.model_audit_flags; if iscell(F); F = [F{:}]; end
    clean = {};
    for i = 1:min(40, numel(F))
        f = F(i);
        g = struct();
        sv = lower(localGet(f,'severity','low'));
        if ~ismember(sv, validSev); sv = 'low'; end
        g.severity = sv;
        g.model_component        = localGet(f,'model_component','unspecified');
        g.issue                  = localGet(f,'issue','');
        g.evidence_from_summary  = localGet(f,'evidence_from_summary','');
        g.recommended_human_review = localGet(f,'recommended_human_review','Human review required.');
        g.suggested_experiment   = localGet(f,'suggested_experiment','');
        clean{end+1} = g; %#ok<AGROW>
    end
    audit.model_audit_flags = [clean{:}];

    if ~isfield(audit,'calibration_priorities'); audit.calibration_priorities = {}; end
    if ~isfield(audit,'minimum_real_measurements_needed'); audit.minimum_real_measurements_needed = {}; end
    if ~isfield(audit,'manuscript_limitations_text'); audit.manuscript_limitations_text = ''; end
    audit.calibration_priorities = localToCellstr(audit.calibration_priorities);
    audit.minimum_real_measurements_needed = localToCellstr(audit.minimum_real_measurements_needed);

    % --- governance metadata ---
    audit.parameters_modified = false;   % this function never edits the model
    audit.data_label = 'simulation-generated synthetic data - NOT real industrial data';
    audit.audit_note = ['AI-assisted model auditing only. No automatic recalibration ', ...
        'performed; human supervision required.'];
    if usedMock
        audit.source = 'MOCK_fallback';
        if ~contains(lower(string(audit.manuscript_limitations_text)),'mock')
            audit.manuscript_limitations_text = ['[MOCK] ' char(audit.manuscript_limitations_text)];
        end
    else
        audit.source = 'gemini_live';
    end
    % Scrub operational directives from the free-text limitations field (no footer;
    % short field embedded in a JSON artifact).
    audit.manuscript_limitations_text = gemini_sanitize_report(char(audit.manuscript_limitations_text), false);
    audit.n_high_severity = sum(arrayfun(@(f) strcmpi(f.severity,'high'), audit.model_audit_flags));
end

% ======================================================================
function c = localToCellstr(x)
    if isempty(x); c = {}; return; end
    if ischar(x); c = {x};
    elseif isstring(x); c = cellstr(x);
    elseif iscell(x); c = cellfun(@(e) char(string(e)), x, 'UniformOutput', false);
    else; c = {};
    end
    c = c(:);
end

function v = localGet(s, f, default)
    v = default;
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f))
        try
            v = char(string(s.(f)));
        catch
            v = default;
        end
    end
end

function txt = localReadOrEmpty(fpath)
    if exist(fpath,'file') == 2
        try
            txt = fileread(fpath);
        catch
            txt = '';
        end
    else
        txt = '';
    end
end

function s = localStripFences(s)
    s = char(s);
    s = regexprep(s,'^\s*```[a-zA-Z]*\s*','');
    s = regexprep(s,'\s*```\s*$','');
end
