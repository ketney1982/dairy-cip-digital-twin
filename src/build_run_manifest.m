% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function manifest = build_run_manifest(opts)
%BUILD_RUN_MANIFEST  Reproducibility/consistency manifest for a study run.
%
%   manifest = BUILD_RUN_MANIFEST() writes results/run_manifest.json capturing a
%   run id, timestamp, the configured scenario count, row counts of the major
%   artifacts, a lightweight fingerprint (bytes + datenum + MD5 when available)
%   per major file, the Gemini model name (NEVER the API key), and whether the
%   generative-AI artifacts were produced LIVE or in MOCK mode. It also raises
%   CONSISTENCY WARNINGS, e.g. dataset row count vs dataset_summary.n_total
%   mismatch, or a pipeline sentinel left in the RUNNING state.
%
%   OPTS (optional): .run_id (reuse a shared id), .out_path,
%       .pipeline_status (OK|PARTIAL|FAILED), .pipeline_steps.
%
%   The API key is NEVER read or written. All data are SIMULATION-GENERATED
%   SYNTHETIC data.
%
%   See also: RUN_FULL_PIPELINE, BUILD_AI_DECISION_DOSSIER.

    if nargin < 1 || isempty(opts); opts = struct(); end
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(here);
    resDir  = fullfile(root,'results');
    dataDir = fullfile(root,'data');
    if ~exist(resDir,'dir'); mkdir(resDir); end
    outPath = localOpt(opts,'out_path', fullfile(resDir,'run_manifest.json'));

    manifest = struct();
    manifest.run_id = localOpt(opts,'run_id', localRunId());
    manifest.timestamp = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
    manifest.data_label = 'simulation-generated synthetic data - NOT real industrial data';
    manifest.public_release_note = ['All retained artifacts are either source, ', ...
        'required model assets, simulation-generated synthetic data, or documented ', ...
        'regenerable results for manuscript review.'];

    % ---- Configured scenario count --------------------------------------
    envN = getenv('CIP_N_SCENARIOS');
    if isempty(envN); manifest.CIP_N_SCENARIOS = 'unset (default 5000)';
    else; manifest.CIP_N_SCENARIOS = envN; end
    cfgMode = lower(strtrim(getenv('CIP_GEMINI_MODE')));
    if isempty(cfgMode); cfgMode = 'auto'; end
    manifest.configured_gemini_mode = cfgMode;

    % ---- Row counts -----------------------------------------------------
    dsPath  = fullfile(dataDir,'dairy_cip_synthetic_dataset.csv');
    aiPath  = fullfile(dataDir,'dairy_cip_ai_designed_dataset.csv');
    sumPath = fullfile(resDir,'dataset_summary.json');
    valPath = fullfile(resDir,'dataset_validation_report.txt');
    parPath = fullfile(resDir,'pareto_solutions.csv');

    combPath = fullfile(dataDir,'dairy_cip_combined_dataset.csv');
    [nDataset, nDatasetSucc] = localCsvRows(dsPath);
    [nAI, nAISucc]           = localCsvRows(aiPath);
    [nComb, ~]               = localCsvRows(combPath);
    [nSummary, summarySrc]   = localSummaryInfo(sumPath);
    nValidation = localValidationN(valPath);
    [nPareto, ~] = localCsvRows(parPath);

    rc = struct();
    rc.dataset_rows            = nDataset;          % base synthetic dataset
    rc.base_dataset_rows       = nDataset;
    rc.dataset_success_rows    = nDatasetSucc;
    rc.ai_designed_rows        = nAI;
    rc.ai_designed_success_rows= nAISucc;
    rc.combined_dataset_rows   = nComb;             % base + AI-designed (closed loop)
    rc.dataset_summary_n_total = nSummary;
    rc.dataset_summary_source  = summarySrc;        % which dataset the summary describes
    rc.validation_total_rows   = nValidation;
    rc.pareto_solutions_rows   = nPareto;
    manifest.row_counts = rc;

    % ---- File fingerprints (major artifacts) ----------------------------
    files = { ...
        dsPath; aiPath; sumPath; valPath; parPath; ...
        fullfile(resDir,'surrogate_models.mat'); ...
        fullfile(resDir,'surrogate_metrics.csv'); ...
        fullfile(resDir,'selected_policy_config.json'); ...
        fullfile(resDir,'ai_experiment_design.json'); ...
        fullfile(resDir,'ai_hypotheses.json'); ...
        fullfile(resDir,'ai_hypothesis_validation.csv'); ...
        fullfile(resDir,'model_equation_summary.json'); ...
        fullfile(resDir,'model_audit_report.json'); ...
        fullfile(resDir,'plausibility_audit.json'); ...
        fullfile(resDir,'ai_supervisory_recommendation.json'); ...
        fullfile(resDir,'ai_closed_loop_trace.json'); ...
        fullfile(resDir,'policy_portfolio_results.csv')};
    fp = struct([]);
    for i = 1:numel(files)
        s = localFingerprint(files{i});
        s.name = localRel(files{i}, root);
        if isempty(fp); fp = s; else; fp(end+1) = s; end %#ok<AGROW>
    end
    manifest.artifacts = fp;

    % ---- Gemini model + LIVE/MOCK detection -----------------------------
    gm = getenv('GEMINI_MODEL');
    if isempty(gm); gm = 'gemini-3.5-flash (default)'; end
    manifest.gemini_model = gm;                 % model name only; never the key
    manifest.gemini_key_configured = ~isempty(getenv('GEMINI_API_KEY')); % boolean only (no value)
    [overall, perArtifact] = localGeminiMode(resDir);
    manifest.gemini_mode = overall;             % LIVE | MOCK | MIXED | UNKNOWN
    manifest.gemini_mode_by_artifact = perArtifact;

    % ---- Pipeline status ------------------------------------------------
    manifest.pipeline_status = localPipelineStatus(resDir, opts);
    manifest.pipeline_steps = localOpt(opts,'pipeline_steps',struct([]));

    % ---- Consistency warnings -------------------------------------------
    W = {};
    % Compare the summary's n_total against the dataset it CLAIMS to describe
    % (source_dataset): the combined set during the closed loop, else the base.
    if contains(lower(summarySrc), 'combined')
        expectedSummaryRows = nComb;  expectedSummaryName = 'combined dataset';
    else
        expectedSummaryRows = nDataset; expectedSummaryName = 'base dataset';
    end
    if isfinite(expectedSummaryRows) && isfinite(nSummary) && expectedSummaryRows ~= nSummary
        W{end+1} = sprintf(['dataset_summary.n_total (%d, source=%s) != %s rows (%d): ', ...
            'summary may be stale; rebuild build_dataset_summary.'], ...
            nSummary, summarySrc, expectedSummaryName, expectedSummaryRows);
    end
    if isfinite(nValidation) && isfinite(nDataset) && nValidation ~= nDataset
        W{end+1} = sprintf('Validation total rows (%d) != dataset rows (%d).', nValidation, nDataset);
    end
    sentinel = fullfile(resDir,'_pipeline_status.txt');
    if exist(sentinel,'file')==2
        try
            st = strtrim(fileread(sentinel));
            if contains(upper(st),'RUNNING') && ~contains(upper(st),'DONE')
                W{end+1} = ['Pipeline sentinel _pipeline_status.txt is still RUNNING ', ...
                    '(a previous run may have crashed or is still in progress).'];
            end
        catch
            % ignore unreadable sentinel
        end
    end
    if strcmp(overall,'MIXED')
        W{end+1} = 'Gemini artifacts are a MIX of LIVE and MOCK; interpret reports accordingly.';
    end
    if ischar(manifest.pipeline_status) || isstring(manifest.pipeline_status)
        ps = upper(char(string(manifest.pipeline_status)));
        if strcmp(ps,'FAILED')
            W{end+1} = 'Pipeline status is FAILED; public artifacts may be incomplete.';
        elseif strcmp(ps,'PARTIAL')
            W{end+1} = 'Pipeline status is PARTIAL; critical steps passed but non-critical artifacts may be missing or stale.';
        end
    end
    manifest.consistency_warnings = W;
    manifest.consistent = isempty(W);

    % ---- Write ----------------------------------------------------------
    fid = fopen(outPath,'w');
    if fid < 0; error('build_run_manifest:fopen','Cannot write %s', outPath); end
    fwrite(fid, jsonencode(manifest,'PrettyPrint',true), 'char'); fclose(fid);

    fprintf('[build_run_manifest] run_id=%s gemini=%s warnings=%d -> %s\n', ...
        manifest.run_id, overall, numel(W), outPath);
end

% ======================================================================
function id = localRunId()
% Unique-ish id from timestamp + a random suffix (MATLAB context; not a workflow).
    ts = char(datetime('now','Format','yyyyMMdd_HHmmss'));
    id = sprintf('run_%s_%04d', ts, randi(9999));
end

% ======================================================================
function [n, nSucc] = localCsvRows(p)
    n = NaN; nSucc = NaN;
    if exist(p,'file') ~= 2; return; end
    try
        T = readtable(p);
        n = height(T);
        if ismember('simulation_status', T.Properties.VariableNames)
            nSucc = sum(string(T.simulation_status)=="success");
        else
            nSucc = n;
        end
    catch
        % leave NaN
    end
end

function [n, src] = localSummaryInfo(p)
    n = NaN; src = '';
    if exist(p,'file') ~= 2; return; end
    try
        s = jsondecode(fileread(p));
        if isfield(s,'n_total'); n = s.n_total; end
        if isfield(s,'source_dataset'); src = char(string(s.source_dataset)); end
    catch
        % leave defaults
    end
end

function n = localValidationN(p)
    n = NaN;
    if exist(p,'file') ~= 2; return; end
    try
        txt = fileread(p);
        tok = regexp(txt, 'Total rows\s*:\s*(\d+)', 'tokens', 'once');
        if ~isempty(tok); n = str2double(tok{1}); end
    catch
        % leave NaN
    end
end

% ======================================================================
function s = localFingerprint(p)
    s = struct('name','','exists',false,'bytes',0,'datenum',0,'modified','','md5','');
    d = dir(p);
    if isempty(d); return; end
    s.exists = true;
    s.bytes = d.bytes;
    s.datenum = d.datenum;
    s.modified = char(datetime(d.datenum,'ConvertFrom','datenum','Format','yyyy-MM-dd HH:mm:ss'));
    s.md5 = localMD5(p);
end

function h = localMD5(p)
% Best-effort MD5 via Java; empty string if unavailable (graceful fallback).
    h = '';
    try
        fid = fopen(p,'r'); if fid<0; return; end
        bytes = fread(fid, Inf, '*uint8'); fclose(fid);
        md = java.security.MessageDigest.getInstance('MD5');
        dig = md.digest(bytes);
        h = lower(reshape(dec2hex(typecast(dig,'uint8')).',1,[]));
    catch
        h = '';
    end
end

% ======================================================================
function [overall, per] = localGeminiMode(resDir)
% Inspect known artifacts for LIVE vs MOCK markers.
    per = struct();
    modes = {};
    per.experiment_design   = localSrcField(fullfile(resDir,'ai_experiment_design.json'),'source');
    per.hypotheses          = localSrcField(fullfile(resDir,'ai_hypotheses.json'),'source');
    per.model_audit         = localSrcField(fullfile(resDir,'model_audit_report.json'),'source');
    per.supervisory         = localSrcField(fullfile(resDir,'ai_supervisory_recommendation.json'),'explanation_source');
    per.policy              = localMockMarker(fullfile(resDir,'selected_policy_config.json'),'[MOCK');
    per.plausibility_audit  = localMockMarker(fullfile(resDir,'plausibility_audit.json'),'MOCK');
    per.pareto_explanation  = localMockMarker(fullfile(resDir,'gemini_decision_report.txt'),'[MOCK');
    fn = fieldnames(per);
    for i = 1:numel(fn)
        m = per.(fn{i});
        if ~strcmp(m,'absent'); modes{end+1} = m; end %#ok<AGROW>
    end
    if isempty(modes)
        overall = 'UNKNOWN';
    elseif all(strcmp(modes,'LIVE'))
        overall = 'LIVE';
    elseif all(strcmp(modes,'MOCK'))
        overall = 'MOCK';
    else
        overall = 'MIXED';
    end
end

function status = localPipelineStatus(resDir, opts)
% OK|PARTIAL|FAILED from explicit opts or the transient pipeline sentinel.
    status = localOpt(opts, 'pipeline_status', '');
    if ~isempty(status); status = char(string(status)); return; end
    status = 'UNKNOWN';
    sentinel = fullfile(resDir,'_pipeline_status.txt');
    if exist(sentinel,'file') ~= 2; return; end
    try
        txt = fileread(sentinel);
        tok = regexp(txt, 'PIPELINE_STATUS\s*=\s*([A-Z]+)', 'tokens', 'once');
        if ~isempty(tok); status = tok{1}; end
    catch
        status = 'UNKNOWN';
    end
end

function m = localSrcField(p, field)
% 'LIVE'|'MOCK'|'absent' from a .source-like field ('gemini_live'/'MOCK_fallback').
    m = 'absent';
    if exist(p,'file') ~= 2; return; end
    try
        s = jsondecode(fileread(p));
        if isfield(s, field)
            v = lower(char(string(s.(field))));
            if contains(v,'mock'); m = 'MOCK'; elseif contains(v,'live'); m = 'LIVE'; else; m = 'LIVE'; end
        else
            m = 'absent';
        end
    catch
        m = 'absent';
    end
end

function m = localMockMarker(p, marker)
% 'MOCK' if the file contains the marker text, else 'LIVE'; 'absent' if missing.
    m = 'absent';
    if exist(p,'file') ~= 2; return; end
    try
        txt = fileread(p);
        if contains(txt, marker); m = 'MOCK'; else; m = 'LIVE'; end
    catch
        m = 'absent';
    end
end

% ======================================================================
function r = localRel(p, root)
    r = p;
    if startsWith(p, root); r = strrep(extractAfter(p, root+""), filesep, '/'); end
    r = regexprep(char(r), '^/', '');
end

function v = localOpt(opts, field, default)
    if isstruct(opts) && isfield(opts, field) && ~isempty(opts.(field))
        v = opts.(field);
    else
        v = default;
    end
end
