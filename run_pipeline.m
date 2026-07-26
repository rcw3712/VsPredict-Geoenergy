% RUN_PIPELINE.M  Clean-session launcher for VsPredict_Geoenergy_v4.
%
%  This is a SCRIPT (not a function) so that restoredefaultpath can be called.
%  MATLAB requires restoredefaultpath to run in script or base workspace.
%
%  Usage (from MATLAB command window or a clean session):
%    cd E:\VsPredict_Geoenergy_v4
%    run_pipeline
%
%  Do NOT call:
%    main_numerical_pipeline   (run it via this script instead)
%    addpath(genpath(...))     (this script handles the path)

%% 1. Clean path — must be in script workspace
restoredefaultpath;

%% 2. Locate repo root — this script IS in the repo root
repo_root = fileparts(mfilename('fullpath'));
if isempty(repo_root)
    % Called from current directory
    repo_root = pwd;
end
fprintf('[RUN_PIPELINE] repo_root = %s\n', repo_root);

%% 3. Add only explicit paths — no genpath (Rule 1.2)
addpath(repo_root);
addpath(fullfile(repo_root, 'config'));
% MATLAB packages (+core, +models, +gse_report) resolve automatically
% when their parent folder (repo_root) is on the path.

%% 4. Clean workspace and figures
clearvars -except repo_root;
close all;
clc;

%% 5. Delete any parallel pool
pool = gcp('nocreate');
if ~isempty(pool); delete(pool); end

%% 6. Run numerical pipeline
main_numerical_pipeline(repo_root);
