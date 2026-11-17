% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% startup.m
% Portable project startup for the dairy CIP digital twin, plus OPTIONAL MATLAB /
% Simulink Agentic Toolkit hooks. Safe to commit and share:
%   * all paths are derived from this file's location and the user profile
%     (no per-machine absolute paths),
%   * optional toolkit hooks are skipped SILENTLY when not installed (no warning
%     spam for users who do not have the agentic toolkit),
%   * machine-specific settings go in a gitignored startup.local.m.

this_file = mfilename('fullpath');
if isempty(this_file)
    project_root = pwd;
else
    project_root = fileparts(this_file);
end
if isfolder(project_root)
    cd(project_root);
    if isfolder(fullfile(project_root,'src')); addpath(fullfile(project_root,'src')); end
end

% --- Optional Simulink Agentic Toolkit (resolved portably) ------------------
% 1) CIP_SATK_PATH env var if set; else 2) <user home>/.matlab/agentic-toolkits/simulink.
satk_path = getenv('CIP_SATK_PATH');
if isempty(satk_path)
    home = getenv('USERPROFILE');
    if isempty(home); home = getenv('HOME'); end
    if ~isempty(home)
        satk_path = fullfile(home, '.matlab', 'agentic-toolkits', 'simulink');
    end
end
if ~isempty(satk_path) && isfolder(satk_path)
    addpath(satk_path);
    if exist('satk_initialize', 'file') > 0
        try
            satk_initialize;
        catch ME
            warning('SATK:InitFailed', 'satk_initialize failed: %s', ME.message);
        end
    end
    if exist('shareMATLABSession', 'file') == 2
        try
            shareMATLABSession();
        catch ME
            warning('MATLABSession:ShareFailed', 'shareMATLABSession failed: %s', ME.message);
        end
    end
end

% --- Machine-specific overrides (gitignored), if present --------------------
local_startup = fullfile(project_root, 'startup.local.m');
if exist(local_startup, 'file') == 2
    run(local_startup);
end
