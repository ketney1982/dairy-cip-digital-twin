% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function [clean, hits] = gemini_sanitize_report(txt, addFooter)
%GEMINI_SANITIZE_REPORT  Neutralize unsafe operational directives in Gemini text.
%
%   clean = GEMINI_SANITIZE_REPORT(txt) returns a sanitized copy of a free-text
%   string produced by the (post-hoc, governed) Gemini layer in which direct
%   operational directives are neutralized and RESEARCH-ONLY / HUMAN-REVIEWED
%   framing is enforced.
%
%   [clean, hits] = GEMINI_SANITIZE_REPORT(...) also returns a cellstr of the
%   directive phrases that were neutralized (for logging / audit).
%
%   GEMINI_SANITIZE_REPORT(txt, addFooter) appends the mandatory governance
%   footer when addFooter is true (default). Pass false for short JSON string
%   fields where only the in-line directive scrub is wanted.
%
%   What it neutralizes (case-insensitive), e.g.:
%     "implement immediately", "deploy", "roll out", "apply now", "go live",
%     "put into production", bare "immediately", and imperative setpoint
%     commands ("set/adjust/increase/decrease the temperature/flow/NaOH ...").
%   These are rewritten into research-only, human-review phrasing.
%
%   GOVERNANCE: the CIP study is a proof-of-concept on SIMULATION-GENERATED
%   SYNTHETIC DATA. Gemini explains numbers; it must NEVER issue calibrated,
%   directly-actionable plant instructions. This is defense-in-depth alongside
%   the system-prompt rules: even a live model that slips an operational
%   recommendation through has it neutralized here before the artifact is saved.
%   The function is deterministic and makes no network calls.
%
%   See also: GEMINI_EXPLAIN_PARETO, AI_SUPERVISORY_CONTROL_RECOMMENDER,
%             BUILD_AI_DECISION_DOSSIER.

    if nargin < 2 || isempty(addFooter); addFooter = true; end
    if nargin < 1 || isempty(txt); clean = ''; hits = {}; return; end
    clean = char(txt);

    % --- 1. Directive phrase -> research-only rewrites -----------------------
    % Each row: {case-insensitive regex, replacement, short audit label}.
    % Order matters: more specific phrases are handled before generic ones so a
    % bare-word rule (e.g. "immediately") cannot double-rewrite an earlier match.
    rules = {
        '\b(?:please\s+)?implement(?:ed|ing|ation)?\s+immediately\b', ...
            'be evaluated by a qualified human expert before any use (research-only)', 'implement immediately'; ...
        '\bimplement(?:ed|ing|ation)?\s+(?:this|the|these|it)\b', ...
            'have a qualified human expert review whether to investigate', 'implement <recipe>'; ...
        '\bdeploy(?:ed|ing|ment)?\b', ...
            'study further (research-only; not for deployment)', 'deploy'; ...
        '\b(?:roll|rolled|rolling)\s+out\b', ...
            'study further (research-only)', 'roll out'; ...
        '\bput\s+(?:this|it|these)\s+into\s+(?:production|practice|operation)\b', ...
            'reserve this for research-only evaluation', 'put into production'; ...
        '\bapply\s+(?:this|it|these|now|immediately)\b', ...
            'have a human expert assess (research-only)', 'apply now'; ...
        '\bgo\s+live\b', ...
            'remain in research-only evaluation', 'go live'; ...
        '\breal[\s-]?time\s+control\b', ...
            'research-only offline analysis', 'real-time control'; ...
        '\bready\s+for\s+(?:production|deployment|plant\s+use|operation)\b', ...
            'NOT ready for production (research-only)', 'ready for production'; ...
        '\b(?:set|adjust|change|increase|decrease|raise|lower|tune)\s+the\s+', ...
            'a human expert could investigate the ', 'imperative setpoint'; ...
        '\bmust\s+be\s+(?:set|adjusted|changed|increased|decreased|raised|lowered)\b', ...
            'could be studied (research-only) as', 'must be set'; ...
        '\bimmediately\b', ...
            'only after qualified human review', 'immediately' ...
    };

    % MATLAB's regexp engine treats \b as a literal backspace (0x08), NOT as a
    % PCRE word boundary (verified on R2026a: regexpi('we deploy','\bdeploy\b')
    % yields NO match). The rules above are authored with \b for readability;
    % convert each \b to an equivalent zero-width lookaround word boundary that
    % MATLAB honours -- otherwise NONE of the directive rules would ever fire and
    % the sanitizer would only append the footer without neutralizing anything.
    WB = ['(?:(?<=[A-Za-z0-9_])(?![A-Za-z0-9_])|' ...
          '(?<![A-Za-z0-9_])(?=[A-Za-z0-9_]))'];
    for r = 1:size(rules,1)
        rules{r,1} = strrep(rules{r,1}, '\b', WB);
    end

    hits = cell(1, size(rules,1));
    nh = 0;
    for r = 1:size(rules,1)
        pat = rules{r,1}; rep = rules{r,2}; lab = rules{r,3};
        if ~isempty(regexpi(clean, pat, 'once'))
            nh = nh + 1;
            hits{nh} = lab;
            clean = regexprep(clean, pat, rep, 'ignorecase');
        end
    end
    hits = hits(1:nh);

    % --- 2. Mandatory research-only / human-reviewed governance footer ------
    if addFooter
        marker = 'RESEARCH-ONLY, HUMAN-REVIEWED';
        if isempty(regexpi(clean, marker, 'once'))
            footer = strjoin({ ...
                '', ...
                '----------------------------------------------------------------', ...
                ['GOVERNANCE: ' marker '. This text explains SIMULATION-GENERATED'], ...
                'SYNTHETIC, proof-of-concept results. It is NOT a calibrated or', ...
                'operational recommendation. No setpoint herein may be applied', ...
                'without validation against plant data, qualified human review and', ...
                'food-safety sign-off.'}, newline);
            clean = [clean, newline, footer];
        end
    end
end
