% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function status = load_dotenv(envPath, opts)
%LOAD_DOTENV  Load KEY=VALUE pairs from a .env file into the process environment.
%
%   status = LOAD_DOTENV() looks for a .env file in the project root (the parent
%   of this src folder) and fills each KEY as an environment variable via setenv
%   (NOT assignin; the base workspace is never touched).
%
%   status = LOAD_DOTENV(envPath) uses an explicit .env path.
%   status = LOAD_DOTENV(envPath, opts) honours option struct opts:
%       opts.override (logical, default FALSE) — when TRUE, .env values overwrite
%           keys that are already set in the process environment.  Use this only
%           to force-refresh secrets (e.g. after editing .env mid-session).
%           Default FALSE means SESSION/EXPLICIT values always win.
%
%   ------------------------------------------------------------------
%   CONFIGURATION PRECEDENCE (lowest -> highest):
%     1. Built-in defaults (hardcoded in each script)
%     2. .env file        (fills UNSET keys only; override=false by default)
%     3. Explicit / session setenv()  (always wins when override=false)
%
%   Example: to smoke-test with 50 scenarios even when .env is present:
%       setenv('CIP_N_SCENARIOS','50');    % explicit, wins over .env
%       run('src/run_full_pipeline.m')
%   ------------------------------------------------------------------
%
%   Convenience aliasing for this project's Vite-style names:
%     VITE_GEMINI_API_KEY -> GEMINI_API_KEY   (if the latter is unset)
%     VITE_GEMINI_MODEL   -> GEMINI_MODEL     (if the latter is unset)
%
%   Returns a struct: .loaded (logical, file found), .keys (cellstr of keys SET
%   by the file this call), .skipped (cellstr of keys ALREADY SET that were
%   skipped because override=false), .hasGeminiKey (logical).
%   API key VALUES are never printed or returned.
%
%   See also: GEMINI_CALL, GEMINI_RESOLVE_MODE.

    if nargin < 1 || isempty(envPath)
        here = fileparts(mfilename('fullpath'));
        root = fileparts(here);
        envPath = fullfile(root,'.env');
    end
    if nargin < 2 || isempty(opts); opts = struct(); end
    doOverride = isfield(opts,'override') && ~isempty(opts.override) && opts.override;

    status = struct('loaded',false,'keys',{{}},'skipped',{{}},'hasGeminiKey',false);

    if exist(envPath,'file') ~= 2
        status.hasGeminiKey = ~isempty(getenv('GEMINI_API_KEY'));
        return;
    end

    txt = string(fileread(envPath));
    lines = splitlines(txt);
    setKeys = {};
    skipped = {};
    for i = 1:numel(lines)
        ln = strtrim(lines(i));
        if ln == "" || startsWith(ln,"#"); continue; end
        ln = regexprep(ln,'^\s*export\s+','');     % tolerate "export KEY=VAL"
        eqp = strfind(ln,'=');
        if isempty(eqp); continue; end
        key = strtrim(extractBefore(ln, eqp(1)));
        val = strtrim(extractAfter(ln, eqp(1)));
        % strip surrounding single or double quotes
        val = regexprep(val, '^([''"])(.*)\1$', '$2');
        if key == ""; continue; end
        alreadySet = ~isempty(getenv(char(key)));
        if alreadySet && ~doOverride
            % Session / explicit value wins (precedence: default < .env < explicit).
            skipped{end+1} = char(key); %#ok<AGROW>
        else
            setenv(char(key), char(val));
            setKeys{end+1} = char(key); %#ok<AGROW>
        end
    end

    % Alias Vite-style names to the canonical ones expected by gemini_call.
    % Apply the same override logic: only fill the canonical name if it is unset
    % (or if override is requested).
    fileHas = @(k) any(strcmp(setKeys, k));
    canonical = {'GEMINI_API_KEY', 'VITE_GEMINI_API_KEY'; ...
                 'GEMINI_MODEL',   'VITE_GEMINI_MODEL'};
    for k = 1:size(canonical,1)
        canon = canonical{k,1}; vite = canonical{k,2};
        if (fileHas(vite) || ~isempty(getenv(vite))) && ...
           (doOverride || isempty(getenv(canon)))
            setenv(canon, getenv(vite));
        end
    end

    status.loaded = true;
    status.keys = setKeys;
    status.skipped = skipped;
    status.hasGeminiKey = ~isempty(getenv('GEMINI_API_KEY'));
end
