% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% RUN_GENERATE_FULL  Driver to generate the full synthetic dataset headlessly.
%
%   Sets N=5000, runs run_cip_scenarios, and writes a completion sentinel file
%   (results/_gen_status.txt) so a polling caller can detect completion without
%   holding a long synchronous connection. Reproducible (rng inside the runner).
%
%   This is a convenience driver; the canonical entry point remains
%   run_full_pipeline.m. Produces SIMULATION-GENERATED SYNTHETIC DATA.

here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here);
resDir = fullfile(root,'results'); if ~exist(resDir,'dir'); mkdir(resDir); end
sentinel = fullfile(resDir,'_gen_status.txt');

% Mark running.
fid = fopen(sentinel,'w'); fprintf(fid,'RUNNING\n'); fclose(fid);

t0 = tic;
ok = false; msg = '';
try
    setenv('CIP_N_SCENARIOS','5000');
    run(fullfile(here,'run_cip_scenarios.m'));
    ok = true;
catch ME
    msg = ME.message;
end
elapsed = toc(t0);

% Summarize result into the sentinel.
fid = fopen(sentinel,'w');
if ok
    csv = fullfile(root,'data','dairy_cip_synthetic_dataset.csv');
    T = readtable(csv);
    nS = sum(string(T.simulation_status)=="success");
    nF = height(T) - nS;
    fprintf(fid,'DONE ok=1 rows=%d success=%d failed=%d elapsed=%.1f\n', height(T), nS, nF, elapsed);
else
    fprintf(fid,'DONE ok=0 elapsed=%.1f error=%s\n', elapsed, msg);
end
fclose(fid);
fprintf('[run_generate_full] %s (%.1f s)\n', ternary(ok,'SUCCESS','FAILED'), elapsed);

function out = ternary(c,a,b)
    if c; out = a; else; out = b; end
end
