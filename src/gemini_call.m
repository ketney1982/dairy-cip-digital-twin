% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function [text, info] = gemini_call(system_text, user_text, opts)
%GEMINI_CALL  Low-level helper to call the Google Gemini generateContent API.
%
%   [TEXT, INFO] = GEMINI_CALL(SYSTEM_TEXT, USER_TEXT) sends a single-turn
%   request to the Gemini REST API and returns the model's text response.
%
%   [TEXT, INFO] = GEMINI_CALL(SYSTEM_TEXT, USER_TEXT, OPTS) accepts options:
%       OPTS.model        - model id (default getenv('GEMINI_MODEL') or
%                           'gemini-3.5-flash')
%       OPTS.json_only    - true to request responseMimeType=application/json
%                           (default true)
%       OPTS.temperature  - sampling temperature (default 0.2 for determinism)
%       OPTS.max_tokens   - maxOutputTokens (default 2048)
%       OPTS.timeout      - HTTP timeout in seconds (default 90)
%
%   INFO is a struct with fields: .ok (logical), .status, .model, .raw,
%   .error (message if any). On any failure TEXT is '' and INFO.ok is false;
%   the caller is responsible for falling back to a local mock so the
%   pipeline never crashes when Gemini is unavailable.
%
%   The API key is read ONLY from the environment variable GEMINI_API_KEY.
%   It is NEVER hard-coded and never written to disk (project constraint).
%
%   --------------------------------------------------------------------
%   GOVERNANCE NOTE: This helper is the ONLY network entry point to Gemini.
%   Gemini is used exclusively for (a) policy->constraint translation,
%   (b) plausibility auditing of summary statistics, and (c) post-hoc
%   explanation of numerically-derived Pareto solutions. It is NEVER called
%   from inside Simulink or from inside the optimization loop, and is never
%   treated as a source of ground truth.
%   --------------------------------------------------------------------

    if nargin < 3 || isempty(opts); opts = struct(); end
    if ~isfield(opts,'model') || isempty(opts.model)
        m = getenv('GEMINI_MODEL');
        if isempty(m); m = 'gemini-3.5-flash'; end   % fallback; .env overrides
        opts.model = m;
    end
    if ~isfield(opts,'json_only');   opts.json_only   = true;  end
    if ~isfield(opts,'temperature'); opts.temperature = 0.2;   end
    % NOTE: thinking-capable models (e.g. gemini-2.5-pro) spend part of the
    % output-token budget on internal reasoning (usageMetadata.thoughtsTokenCount).
    % The budget must cover BOTH the thinking and the visible answer, otherwise
    % the response finishes with finishReason=MAX_TOKENS and carries no
    % content.parts. 8192 gives ample headroom for the JSON outputs used here.
    if ~isfield(opts,'max_tokens');  opts.max_tokens  = 8192;  end
    if ~isfield(opts,'timeout');     opts.timeout     = 180;   end

    % Resolve the UNIFORM execution mode (auto|mock|live). Because every Gemini
    % call site routes through this function, resolving the mode here applies it
    % uniformly to all of them. See gemini_resolve_mode for the precedence.
    mode = gemini_resolve_mode(opts);

    text = '';
    info = struct('ok',false,'status','','model',opts.model,'raw','', ...
                  'error','','mode',mode);

    % MOCK mode: never touch the network. Return immediately (text='') so the
    % caller emits its deterministic, clearly-labelled MOCK output. This is what
    % makes the whole Gemini layer offline-deterministic when mock is requested.
    if strcmp(mode,'mock')
        info.status = 'mock_mode';
        info.error  = 'Gemini mode=mock (forced offline; no network call attempted)';
        return;
    end

    api_key = getenv('GEMINI_API_KEY');
    if isempty(api_key)
        % Best-effort: load a project .env (maps VITE_GEMINI_API_KEY too).
        try
            here = fileparts(mfilename('fullpath'));
            if exist(fullfile(here,'load_dotenv.m'),'file')==2
                load_dotenv();
                api_key = getenv('GEMINI_API_KEY');
            end
        catch
            % ignore; handled below
        end
    end
    if isempty(api_key)
        if strcmp(mode,'live')
            % mode=live explicitly requested a network call: report the missing
            % key loudly, but still let the caller fall back to MOCK (mock-safe).
            info.error  = ['GEMINI_API_KEY not set but mode=live was requested; ' ...
                           'falling back to MOCK'];
            info.status = 'no_api_key_live';
        else
            info.error  = 'GEMINI_API_KEY not set';
            info.status = 'no_api_key';
        end
        return;   % caller must handle the mock fallback
    end
    % Refresh model id from env in case .env supplied GEMINI_MODEL just now.
    if (~isfield(opts,'model') || isempty(opts.model)) && ~isempty(getenv('GEMINI_MODEL'))
        opts.model = getenv('GEMINI_MODEL');
        info.model = opts.model;
    end

    % ---- Build request body (struct -> JSON). Cell wrappers force JSON arrays.
    user_content = struct('role','user','parts',{{struct('text',user_text)}});
    body = struct();
    body.contents = {user_content};
    if ~isempty(system_text)
        body.systemInstruction = struct('parts',{{struct('text',system_text)}});
    end
    gencfg = struct('temperature',opts.temperature, ...
                    'maxOutputTokens',opts.max_tokens);
    if opts.json_only
        gencfg.responseMimeType = 'application/json';
    end
    body.generationConfig = gencfg;

    url = sprintf(['https://generativelanguage.googleapis.com/v1beta/' ...
                   'models/%s:generateContent?key=%s'], opts.model, api_key);

    web = weboptions('MediaType','application/json', ...
                     'RequestMethod','post', ...
                     'Timeout',opts.timeout, ...
                     'ContentType','json');

    try
        resp = webwrite(url, body, web);
        info.raw = resp;
        cand = resp.candidates;
        if iscell(cand); cand = cand{1}; else; cand = cand(1); end

        % Capture finish reason if present (STOP, MAX_TOKENS, SAFETY, ...).
        fr = '';
        if isfield(cand,'finishReason'); fr = char(string(cand.finishReason)); end

        % A truncated/blocked response may carry no content.parts. Detect this
        % explicitly and report a clear status so the caller can fall back to a
        % deliberate mock instead of crashing on a missing field.
        hasParts = isfield(cand,'content') && isstruct(cand.content) ...
                   && isfield(cand.content,'parts') && ~isempty(cand.content.parts);
        if ~hasParts
            info.status = 'no_parts';
            if ~isempty(fr)
                info.error = sprintf('No content.parts (finishReason=%s)', fr);
            else
                info.error = 'No content.parts in response';
            end
            text = '';
            return;
        end

        parts = cand.content.parts;
        if iscell(parts); parts = parts{1}; else; parts = parts(1); end
        text = parts.text;
        info.ok = true;
        info.status = 'ok';
    catch ME
        info.error  = ME.message;
        info.status = 'http_error';
        text = '';
    end
end
