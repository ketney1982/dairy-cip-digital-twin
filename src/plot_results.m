% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% PLOT_RESULTS  Generate manuscript figures with the Python asset pipeline.
%
%   MATLAB is the data producer in this project. Publication figures are
%   rendered by the authors' local plotting script manuscript/make_figures.py,
%   which is not distributed with the public repository, from CSV/JSON
%   artifacts in data/ and results/ (files per figure: docs/methodology_note.md,
%   Section 11). This script intentionally does not create fallback MATLAB figures:
%   if the Python renderer fails, the pipeline should report the real problem
%   instead of silently writing lower-quality plots.
%
%   Required core inputs:
%     data/dairy_cip_synthetic_dataset.csv
%     results/pareto_solutions.csv
%     results/surrogate_pred_vs_obs.csv
%     results/surrogate_metrics.csv
%     results/fig2_kde.csv
%     results/fig2_dist_stats.csv
%     results/fig3_correlation.csv
%     results/fig4_sensitivity.csv
%     results/figS1_phase_summary.csv
%
%   Optional figure-specific inputs are skipped by make_figures.py when absent:
%     results/demo_timeseries_*.csv
%     results/counterfactual_cip_results.csv
%     results/policy_portfolio_results.csv
%
%   Set CIP_PYTHON_CMD to override the Python command, e.g. "py -3".

here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here);

scriptPath = fullfile(root, 'manuscript', 'make_figures.py');
if exist(scriptPath, 'file') ~= 2
    error('plot_results:noPythonScript', ['Python figure script not found:\n  %s\n' ...
        'The plotting scripts are not distributed; the data underlying each figure\n' ...
        'are listed in docs/methodology_note.md (Section 11).'], scriptPath);
end

required = { ...
    fullfile(root, 'data', 'dairy_cip_synthetic_dataset.csv'); ...
    fullfile(root, 'results', 'pareto_solutions.csv'); ...
    fullfile(root, 'results', 'surrogate_pred_vs_obs.csv'); ...
    fullfile(root, 'results', 'surrogate_metrics.csv')};
for i = 1:numel(required)
    if exist(required{i}, 'file') ~= 2
        error('plot_results:missingArtifact', ...
            'Required figure input is missing:\n  %s', required{i});
    end
end

fprintf('\n[plot_results] Regenerating MATLAB figure-data exports.\n');
export_figure_data();
augment_figure_derived();

fprintf('\n[plot_results] Running Python figure generator:\n  %s\n', scriptPath);
[status, cmdOut] = system(localPythonCommand(scriptPath));
if ~isempty(strtrim(cmdOut))
    fprintf('%s\n', cmdOut);
end
if status ~= 0
    error('plot_results:pythonFailed', ...
        'Python figure generator failed with status %d.', status);
end

fprintf('[plot_results] Python figures written to %s\n', fullfile(root, 'figures'));

%% ===== Local functions ======================================================
function cmd = localPythonCommand(scriptPath)
    pythonCmd = strtrim(getenv('CIP_PYTHON_CMD'));
    if isempty(pythonCmd)
        pythonCmd = 'python';
    end
    cmd = sprintf('%s "%s"', pythonCmd, scriptPath);
end
