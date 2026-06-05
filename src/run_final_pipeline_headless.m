% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% RUN_FINAL_PIPELINE_HEADLESS  Produce the final, consistent N=5000 artifacts.
%
%   Convenience driver for an unattended full run: forces N=5000, executes the
%   canonical run_full_pipeline, and writes a completion sentinel
%   (results/_pipeline_status.txt) so a polling caller can detect completion.
%
%   Produces SIMULATION-GENERATED SYNTHETIC DATA.

here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here);
resDir = fullfile(root,'results'); if ~exist(resDir,'dir'); mkdir(resDir); end
sentinel = fullfile(resDir,'_pipeline_status.txt');
fid=fopen(sentinel,'w'); fprintf(fid,'RUNNING\n'); fclose(fid);

t0 = tic; ok=false; msg='';
try
    setenv('CIP_N_SCENARIOS','5000');     % final study size
    run(fullfile(here,'run_full_pipeline.m'));
    ok = true;
catch ME
    msg = ME.message;
end
el = toc(t0);

fid=fopen(sentinel,'w');
if ok
    fprintf(fid,'DONE ok=1 elapsed=%.1f\n', el);
else
    fprintf(fid,'DONE ok=0 elapsed=%.1f error=%s\n', el, msg);
end
fclose(fid);
fprintf('[run_final_pipeline_headless] done ok=%d (%.1f s)\n', ok, el);
