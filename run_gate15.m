% RUN_GATE15.M  Cross-run reproducibility (Gate 15).
%
%  Run this SCRIPT in a CLEAN MATLAB session AFTER two separate run_pipeline runs.
%  Compares specified runs and writes GATE15_CROSS_RUN_REPRODUCIBILITY_REPORT.md.
%
%  Usage:
%    cd E:\VsPredict_Geoenergy_v4
%    run_gate15
%
%  Or specify runs explicitly:
%    run1_folder = 'runs\run_YYYYMMDD_HH1';
%    run2_folder = 'runs\run_YYYYMMDD_HH2';
%    run_gate15

%% Configuration
here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fullfile(here,'config'));
cfg = config_geoenergy_v4();

% Auto-detect two most recent runs if not specified
if ~exist('run1_folder','var') || ~exist('run2_folder','var')
    runs_root = fullfile(here, cfg.output.runs_dir);
    d = dir(fullfile(runs_root,'run_*'));
    d = d([d.isdir]);
% Filter: only runs with FROZEN_NUMERICAL_RUN.mat (completed)
is_complete = false(size(d));
for di=1:numel(d)
    is_complete(di) = isfile(fullfile(d(di).folder,d(di).name,...
        '09_frozen','FROZEN_NUMERICAL_RUN.mat'));
end
d = d(is_complete);
assert(numel(d)>=2,'Gate 15 requires at least 2 completed runs. Found %d.',numel(d));
% Sort by name descending (run_YYYYMMDD_HHMMSS → chronological)
[~,ix] = sort(string({d.name}),'descend');
    if numel(d) < 2
        error('Gate15:InsufficientRuns','Need at least 2 completed runs in runs/. Found %d.', numel(d));
    end
    run1_folder = fullfile(runs_root, d(ix(1)).name);
    run2_folder = fullfile(runs_root, d(ix(2)).name);
    fprintf('Auto-detected:\n  Run 1: %s\n  Run 2: %s\n', run1_folder, run2_folder);
end

%% Load both frozen runs
mat1 = fullfile(run1_folder,'09_frozen','FROZEN_NUMERICAL_RUN.mat');
mat2 = fullfile(run2_folder,'09_frozen','FROZEN_NUMERICAL_RUN.mat');
if ~isfile(mat1); error('Gate15:Missing','Run 1 frozen MAT not found: %s', mat1); end
if ~isfile(mat2); error('Gate15:Missing','Run 2 frozen MAT not found: %s', mat2); end
S1 = load(mat1); r1 = S1.run;
S2 = load(mat2); r2 = S2.run;
fprintf('Loaded:\n  Run 1 ID: %s\n  Run 2 ID: %s\n', r1.id, r2.id);

%% Define checks
checks = {
    'fold_hash',          r1.fold_hash,            r2.fold_hash,            0;
    'n_train',            r1.n_train,               r2.n_train,              0;
    'n_seg0',             r1.n_seg0,                r2.n_seg0,               0;
    'n_pop_A',            r1.n_pop_A,               r2.n_pop_A,              0;
    'n_pop_B',            r1.n_pop_B,               r2.n_pop_B,              0;
    'deploy_name',        r1.deploy_name,           r2.deploy_name,          0;
    'deploy_r2_WA',       r1.deploy_r2_WA,          r2.deploy_r2_WA,         1e-4;
    'S1_features',        strjoin(r1.fs.S1_features,','), strjoin(r2.fs.S1_features,','), 0;
    'S2_features',        strjoin(r1.fs.S2_features,','), strjoin(r2.fs.S2_features,','), 0;
    'hp_pnn_spread',      r1.hyperparams.pnn.spread, r2.hyperparams.pnn.spread, 1e-10;
    'ridge_lambda',       r1.meta_models.ridge.lambda, r2.meta_models.ridge.lambda, 1e-10;
    'ridge_r2_te',        r1.meta_metrics.ridge.R2_te, r2.meta_metrics.ridge.R2_te, 1e-4;
    'eval_popA_n',        r1.eval_popA.n,           r2.eval_popA.n,          0;
    'eval_popA_r2',       r1.eval_popA.R2_raw,      r2.eval_popA.R2_raw,     1e-4;
    'eval_popA_rmse',     r1.eval_popA.RMSE_raw,    r2.eval_popA.RMSE_raw,   1e-4;
    'eval_popA_bias',     r1.eval_popA.bias_raw,    r2.eval_popA.bias_raw,   1e-4;
    'eval_popB_n',        r1.eval_popB.n,           r2.eval_popB.n,          0;
    'eval_popB_r2',       r1.eval_popB.R2_raw,      r2.eval_popB.R2_raw,     1e-4;
    'eval_popB_rmse',     r1.eval_popB.RMSE_raw,    r2.eval_popB.RMSE_raw,   1e-4;
    'eval_popB_bias',     r1.eval_popB.bias_raw,    r2.eval_popB.bias_raw,   1e-4;
    'geomech_n_eval',     r1.geomech.n_eval,        r2.geomech.n_eval,       0;
    'geomech_valid_pct',  r1.geomech.valid_pct,     r2.geomech.valid_pct,    1e-4;
    'preproc_hash',       r1.preproc_dev.hash,      r2.preproc_dev.hash,     0;
};

%% Run checks
n_pass=0; n_fail=0; n_warn=0;
rows={};
fprintf('\n%-30s  %-30s  %-30s  %-8s\n','CHECK','RUN1','RUN2','STATUS');
fprintf('%s\n',repmat('-',1,100));
for ci=1:size(checks,1)
    name=checks{ci,1}; v1=checks{ci,2}; v2=checks{ci,3}; tol=checks{ci,4};
    if ischar(v1)||isstring(v1)
        pass=strcmp(char(v1),char(v2)); diff_val=NaN;
    else
        diff_val=abs(v1-v2);
        if tol==0; pass=diff_val<1e-10; else; pass=diff_val<=tol; end
    end
    if pass; status='PASS'; n_pass=n_pass+1;
    else;     status='FAIL'; n_fail=n_fail+1; end
    v1s=num2str_safe(v1); v2s=num2str_safe(v2);
    fprintf('%-30s  %-30s  %-30s  %s\n',name,v1s(1:min(end,29)),v2s(1:min(end,29)),status);
    rows{end+1}={name,v1s,v2s,status,num2str(tol)};
end

%% Write report
T_rep=cell2table(vertcat(rows{:}),'VariableNames',{'CHECK','RUN1','RUN2','STATUS','TOLERANCE'});
gate15_pass=(n_fail==0);
status_str=char('PASS'*(gate15_pass)+'FAIL'*(~gate15_pass));
report_path=fullfile(here,'runs','GATE15_CROSS_RUN_REPRODUCIBILITY_REPORT.md');
fid=fopen(report_path,'w');
fprintf(fid,'# GATE15_CROSS_RUN_REPRODUCIBILITY_REPORT.md\n\n');
fprintf(fid,'Run 1: %s\nRun 2: %s\n',r1.id,r2.id);
fprintf(fid,'MATLAB: %s\n\n',r1.cfg.study.name);
fprintf(fid,'## Result: GATE_15 = %s\n\n',status_str);
fprintf(fid,'%d/%d checks PASS | %d FAIL\n\n',n_pass,n_pass+n_fail,n_fail);
fprintf(fid,'| Check | Run 1 | Run 2 | Status | Tol |\n|---|---|---|---|---|\n');
for ri=1:numel(rows)
    r=rows{ri};
    fprintf(fid,'| %s | %s | %s | %s | %s |\n',r{1},r{2},r{3},r{4},r{5});
end
fclose(fid);

% Also save as CSV
writetable(T_rep, fullfile(here,'runs','GATE15_CHECKS.csv'));

%% Report
fprintf('\n%s\n',repmat('=',1,60));
fprintf('  GATE_15 = %s  (%d/%d PASS)\n',status_str,n_pass,n_pass+n_fail);
fprintf('  Report: %s\n',report_path);
fprintf('%s\n\n',repmat('=',1,60));
if ~gate15_pass
    fprintf('FAILED checks require investigation before publication.\n');
    fprintf('Stochastic models may have small differences — check tolerance.\n');
end

function s=num2str_safe(v)
if ischar(v)||isstring(v); s=char(v); elseif isnumeric(v); s=num2str(v,'%.6g'); else; s='?'; end
end
