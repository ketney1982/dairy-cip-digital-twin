% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function mode = gemini_resolve_mode(opts)
%GEMINI_RESOLVE_MODE  Resolve the uniform Gemini execution mode: auto|mock|live.
%
%   mode = GEMINI_RESOLVE_MODE()      resolves from the environment / default.
%   mode = GEMINI_RESOLVE_MODE(opts)  lets an explicit opts.mode override it.
%
%   PRECEDENCE (highest first):
%     1. opts.mode             - explicit per-call override ('auto'|'mock'|'live')
%     2. opts.force_mock==true - backward-compatible shortcut, equivalent to 'mock'
%     3. CIP_GEMINI_MODE env   - session / .env setting
%     4. 'auto'                - default
%
%   MODES:
%     'auto' - attempt a LIVE call iff GEMINI_API_KEY is set; otherwise the caller
%              falls back to a clearly-labelled MOCK. (Backward-compatible default.)
%     'mock' - never touch the network; GEMINI_CALL short-circuits so EVERY caller
%              produces its deterministic, clearly-labelled MOCK output.
%     'live' - attempt a LIVE call; if the key is missing or the call fails the
%              caller still falls back to MOCK (the pipeline never crashes), but
%              the missing-key condition is reported more loudly.
%
%   This single resolver is applied centrally inside GEMINI_CALL, so that ALL
%   Gemini call sites honour the same mode uniformly (not just some of them).
%   Every Gemini output describes SIMULATION-GENERATED SYNTHETIC DATA and is
%   post-hoc / human-reviewed only; it is never used inside the solver/optimizer.
%
%   See also: GEMINI_CALL.

    if nargin < 1 || isempty(opts); opts = struct(); end
    mode = '';

    % 1. Explicit opts.mode wins.
    if isstruct(opts) && isfield(opts,'mode') && ~isempty(opts.mode)
        mode = lower(strtrim(char(string(opts.mode))));
    end

    % 2. Backward-compat: opts.force_mock shortcut.
    if isempty(mode) && isstruct(opts) && isfield(opts,'force_mock') ...
            && ~isempty(opts.force_mock) && opts.force_mock
        mode = 'mock';
    end

    % 3. Environment (session or .env).
    if isempty(mode)
        envm = lower(strtrim(getenv('CIP_GEMINI_MODE')));
        if ~isempty(envm); mode = envm; end
    end

    % 4. Default.
    if isempty(mode); mode = 'auto'; end

    % Validate; anything unrecognised degrades safely to 'auto'.
    if ~ismember(mode, {'auto','mock','live'})
        warning('gemini_resolve_mode:badMode', ...
            'Unknown Gemini mode "%s"; using "auto".', mode);
        mode = 'auto';
    end
end
