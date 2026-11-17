% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function audit = gemini_plausibility_auditor()
%GEMINI_PLAUSIBILITY_AUDITOR  AI-assisted plausibility audit of the dataset summary.
%
%   audit = GEMINI_PLAUSIBILITY_AUDITOR() sends the compact dataset summary
%   (results/dataset_summary.json) to Gemini and asks it to FLAG suspicious
%   patterns for HUMAN REVIEW. The result is saved to results/plausibility_audit.json.
%
%   IMPORTANT FRAMING:
%     * This is AI-ASSISTED PLAUSIBILITY AUDITING, not self-calibration.
%     * Gemini does NOT validate the model as true and provides NO industrial
%       validation. No parameter is modified automatically. Any change must be
%       made by a human domain expert after review.
%
%   If GEMINI_API_KEY is missing or the call fails, a deterministic MOCK audit
%   is generated from the summary statistics and clearly labelled.
%
%   See also: BUILD_DATASET_SUMMARY, GEMINI_CALL.

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    resDir = fullfile(root,'results');
    if ~exist(resDir,'dir'); mkdir(resDir); end
    sumPath = fullfile(resDir,'dataset_summary.json');
    outPath = fullfile(resDir,'plausibility_audit.json');

    % Ensure the summary exists (build it if necessary).
    if exist(sumPath,'file') ~= 2
        warning('gemini_plausibility_auditor:noSummary', ...
            'dataset_summary.json missing; running build_dataset_summary.');
        run(fullfile(here,'build_dataset_summary.m'));
    end
    summaryTxt = fileread(sumPath);
    summary = jsondecode(summaryTxt);

    sys = strjoin({ ...
        'You are a cautious simulation plausibility auditor for a dairy CIP', ...
        'digital twin. You receive ONLY summary statistics of a SYNTHETIC', ...
        'dataset (means, ranges, correlations).', ...
        'RULES:', ...
        '1. Do NOT validate the model as true. Do NOT claim industrial validation.', ...
        '2. Use ONLY the provided summary; do not invent data.', ...
        '3. Flag suspicious or implausible patterns that require HUMAN review.', ...
        '4. Suggest which parameters/relationships a human should inspect.', ...
        '5. Do NOT modify or recommend specific parameter values.', ...
        '6. Return VALID JSON ONLY (no markdown), with this shape:', ...
        '{"plausibility_flags":[{"severity":"low|medium|high",', ...
        '  "parameter_or_relationship":"...","issue":"...","recommended_human_check":"..."}],', ...
        ' "model_review_summary":"...","requires_parameter_revision":true|false}'}, newline);

    usr = strjoin({'DATASET SUMMARY (JSON):', summaryTxt}, newline);

    [txt, info] = gemini_call(sys, usr, struct('json_only',true,'temperature',0.1));

    usedMock = false; audit = struct();
    if info.ok
        try
            audit = jsondecode(localStripFences(txt));
        catch ME
            warning('gemini_plausibility_auditor:parse','Bad JSON (%s); using MOCK.', ME.message);
            usedMock = true;
        end
    else
        usedMock = true;
        if ~strcmp(info.status,'mock_mode')   % deliberate mock is not a warning
            warning('gemini_plausibility_auditor:noLLM','Gemini unavailable (%s); using MOCK.', info.status);
        end
    end

    if usedMock
        audit = localMockAudit(summary);
    end
    audit = localNormalizeAudit(audit, usedMock);

    txtOut = jsonencode(audit, 'PrettyPrint', true);
    fid = fopen(outPath,'w');
    if fid < 0; error('gemini_plausibility_auditor:fopen','Cannot write %s', outPath); end
    fwrite(fid, txtOut, 'char'); fclose(fid);

    tag = gemini_mode_tag(info, usedMock);
    fprintf('[gemini_plausibility_auditor] (%s) %d flag(s); revision_needed=%d -> %s\n', ...
        tag, numel(audit.plausibility_flags), audit.requires_parameter_revision, outPath);
end

% ======================================================================
function audit = localMockAudit(summary)
% Heuristic audit derived from the summary's key correlations.
    flags = {};
    kc = struct(); if isfield(summary,'key_correlations'); kc = summary.key_correlations; end
    addflag = @(sev,rel,iss,chk) struct('severity',sev,'parameter_or_relationship',rel, ...
        'issue',iss,'recommended_human_check',chk);

    if isfield(kc,'water_rec_vs_water_L') && ~(kc.water_rec_vs_water_L < -0.05)
        flags{end+1} = addflag('high','water_rec vs water_L', ...
            'Water recovery does not clearly reduce water use (expected negative correlation).', ...
            'Inspect water_consumption block: factor (1 - water_rec).'); %#ok<*AGROW>
    end
    if isfield(kc,'heat_rec_vs_total_energy') && ~(kc.heat_rec_vs_total_energy < -0.05)
        flags{end+1} = addflag('high','heat_rec vs total_energy_kWh', ...
            'Heat recovery does not clearly reduce energy (expected negative correlation).', ...
            'Inspect thermal_energy block: factor (1 - heat_rec).');
    end
    if isfield(kc,'soil0_vs_COD_mgL') && abs(kc.soil0_vs_COD_mgL) < 0.05
        flags{end+1} = addflag('medium','soil0 vs COD_mgL', ...
            'Initial soil shows almost no link to COD (COD may not track soil removal).', ...
            'Inspect cod_organic block and COD_factor.');
    end
    if isfield(kc,'T_C_vs_cleaning_score') && kc.T_C_vs_cleaning_score < 0
        flags{end+1} = addflag('medium','T_C vs cleaning_score', ...
            'Higher temperature appears to reduce cleaning (counter-intuitive).', ...
            'Inspect alpha_T sign and soil_removal kinetics.');
    end
    if isempty(flags)
        flags{end+1} = addflag('low','overall', ...
            'No obvious anomalies in summary correlations; deeper review still advised.', ...
            'Spot-check distributions and tails of cleaning_score and COD_mgL.');
    end

    audit = struct();
    audit.plausibility_flags = [flags{:}];
    audit.model_review_summary = ['[MOCK - GEMINI_API_KEY not configured] ', ...
        'Heuristic review of summary correlations only. This is NOT a validation ', ...
        'of physical correctness; a human domain expert must review the model.'];
    audit.requires_parameter_revision = ~isempty(flags) && ...
        any(arrayfun(@(f) string(f.severity)=="high", audit.plausibility_flags));
end

% ======================================================================
function audit = localNormalizeAudit(audit, usedMock)
    if ~isfield(audit,'plausibility_flags'); audit.plausibility_flags = struct([]); end
    if ~isfield(audit,'model_review_summary'); audit.model_review_summary = ''; end
    if ~isfield(audit,'requires_parameter_revision'); audit.requires_parameter_revision = false; end
    if usedMock && ~contains(string(audit.model_review_summary),'[MOCK]') ...
            && ~contains(lower(string(audit.model_review_summary)),'mock')
        audit.model_review_summary = ['[MOCK] ', char(audit.model_review_summary)];
    end
    % Scrub operational directives from the free-text summary (no footer here;
    % this is a short audit field, not a stand-alone report).
    audit.model_review_summary = gemini_sanitize_report(char(audit.model_review_summary), false);
    audit.audit_note = ['AI-assisted plausibility auditing only. No automatic ', ...
        'recalibration performed; human supervision required.'];
end

% ======================================================================
function s = localStripFences(s)
    s = char(s);
    s = regexprep(s,'^\s*```[a-zA-Z]*\s*','');
    s = regexprep(s,'\s*```\s*$','');
end
