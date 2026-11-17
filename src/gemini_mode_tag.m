% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function tag = gemini_mode_tag(info, usedMock)
%GEMINI_MODE_TAG  Human-readable LIVE / MOCK[...] tag for logging Gemini outputs.
%
%   tag = GEMINI_MODE_TAG(info, usedMock) returns:
%     'LIVE'           - a live Gemini response was used,
%     'MOCK[forced]'   - mock was used because mode=mock was requested,
%     'MOCK[fallback]' - mock was used as a safety fallback (no key / call failed).
%
%   info is the struct returned by GEMINI_CALL (it carries .mode and .status).
%   This keeps the LIVE/MOCK labelling consistent across every Gemini call site.
%
%   See also: GEMINI_CALL, GEMINI_RESOLVE_MODE.

    if nargin < 2 || isempty(usedMock); usedMock = true; end
    if ~usedMock
        tag = 'LIVE';
        return;
    end
    mode = 'auto'; status = '';
    if isstruct(info)
        if isfield(info,'mode')   && ~isempty(info.mode);   mode   = char(string(info.mode));   end
        if isfield(info,'status') && ~isempty(info.status); status = char(string(info.status)); end
    end
    if strcmp(mode,'mock') || strcmp(status,'mock_mode')
        tag = 'MOCK[forced]';
    else
        tag = 'MOCK[fallback]';
    end
end
