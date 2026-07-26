function run = initialize_run(cfg)
% CORE.INITIALIZE_RUN  Create a unique, isolated run folder and metadata.
%
%  Every numerical execution gets a unique RUN_ID. No stale files are read.
%  Rules: §4.1, §4.2, §4.3, §4.4
%
%  Output: run struct with fields:
%    run.id           — 'run_YYYYMMDD_HHMMSS'
%    run.folder       — absolute path to run folder
%    run.cfg          — copy of config (snapshot)
%    run.log_fid      — file ID for run log
%    run.gate         — struct of gate statuses (all FAIL initially)

% ── Clean execution environment (Rule §4.1) ───────────────────────────────────
% NOTE: restoredefaultpath is called by the top-level script, not here.
% This function runs after the clean state is established.
rng('default');  % reset to known state before any model-specific seeding

% ── Generate unique RUN_ID ────────────────────────────────────────────────────
try
    ts = char(datetime('now','Format','yyyyMMdd_HHmmss'));
catch
    ts = datestr(now,'yyyymmdd_HHMMSS'); %#ok<DATST>
end
run.id = sprintf('run_%s', ts);

% ── Create run folder ─────────────────────────────────────────────────────────
% Use repo_root from config (set by main_numerical_pipeline.m) if available.
% This avoids any ambiguity about fileparts() depth from within +core/.
% Fallback: compute from mfilename (correct when +core is ONE level below repo root).
if isfield(cfg, 'repo_root') && ~isempty(cfg.repo_root) && isfolder(cfg.repo_root)
    here = cfg.repo_root;
else
    % Fallback: +core/initialize_run.m → fileparts = +core dir → fileparts = repo root
    here = fileparts(fileparts(mfilename('fullpath')));
    warning('core:initialize_run', ...
        'cfg.repo_root not set; computed as: %s. Set cfg.repo_root in main script.', here);
end
run.repo_root = here;
runs_root = fullfile(here, cfg.output.runs_dir);
run.folder = fullfile(runs_root, run.id);

subfolders = {'00_metadata','01_data_audit','02_preprocessing','03_feature_selection',...
    '04_model_development','05_ablation','06_predictions','07_tables',...
    '08_geomechanics','09_frozen','10_logs','publication_reporting'};

for si = 1:numel(subfolders)
    sf = fullfile(run.folder, subfolders{si});
    if ~isfolder(sf); mkdir(sf); end
end

% ── Open run log ──────────────────────────────────────────────────────────────
log_path = fullfile(run.folder,'10_logs','run_log.txt');
run.log_fid = fopen(log_path,'w');
if run.log_fid < 0
    error('core:initialize_run','Cannot open log file: %s', log_path);
end
run_log(run, '=== RUN INITIALIZED ===');
run_log(run, sprintf('RUN_ID: %s', run.id));
run_log(run, sprintf('Folder: %s', run.folder));
run_log(run, sprintf('MATLAB version: %s', version));
run_log(run, sprintf('Date: %s', ts));

% ── Save config snapshot ──────────────────────────────────────────────────────
run.cfg = cfg;
cfg_path = fullfile(run.folder,'00_metadata','CONFIG_SNAPSHOT.mat');
save(cfg_path,'cfg','-v7.3');

% Write human-readable config snapshot
cfg_txt_path = fullfile(run.folder,'00_metadata','CONFIG_SNAPSHOT.txt');
fid_cfg = fopen(cfg_txt_path,'w');
fprintf(fid_cfg,'RUN_ID: %s\n', run.id);
fprintf(fid_cfg,'Seeds: %s | Canonical: %d\n', num2str(cfg.seeds.all), cfg.seeds.canonical);
fprintf(fid_cfg,'Features S1: %s\n', strjoin(cfg.data.features,','));
fprintf(fid_cfg,'Partition test_frac: %.2f | k-fold: %d\n', cfg.split.test_frac, cfg.split.kfold);
fprintf(fid_cfg,'Execution environment: %s\n', cfg.compute.execution_environment);
fclose(fid_cfg);

% ── Verify CPU execution (Rule §4.2) ─────────────────────────────────────────
if ~strcmp(cfg.compute.execution_environment,'cpu')
    error('core:initialize_run','cfg.compute.execution_environment must be cpu. Got: %s', ...
        cfg.compute.execution_environment);
end

% ── GPU check ─────────────────────────────────────────────────────────────────
gpu_available = false;
try; gpuDeviceCount; gpu_available = true; catch; end
if gpu_available && cfg.compute.allow_gpu
    warning('core:initialize_run','GPU is available but cfg.compute.allow_gpu=false required. Proceeding with CPU.');
end

% ── Parallel pool check ───────────────────────────────────────────────────────
pool = gcp('nocreate');
if ~isempty(pool)
    warning('core:initialize_run','Parallel pool is active. Deleting for determinism.');
    delete(pool);
end

% ── Save RNG and environment metadata ─────────────────────────────────────────
rng_state = rng();
env_path = fullfile(run.folder,'00_metadata','RNG_AND_ENVIRONMENT_REPORT.md');
fid_env = fopen(env_path,'w');
fprintf(fid_env,'# RNG_AND_ENVIRONMENT_REPORT.md\n\n');
fprintf(fid_env,'RUN_ID: %s\n', run.id);
fprintf(fid_env,'MATLAB: %s\n', version);
fprintf(fid_env,'RNG type: %s\n', rng_state.Type);
fprintf(fid_env,'RNG seed (after default reset): N/A (default state)\n');
fprintf(fid_env,'GPU available: %d | GPU allowed: %d\n', gpu_available, cfg.compute.allow_gpu);
fprintf(fid_env,'Parallel pool: none (deleted if existed)\n');
fprintf(fid_env,'Execution environment: %s\n', cfg.compute.execution_environment);
fclose(fid_env);

% ── Initialize gate status ────────────────────────────────────────────────────
gates = {'GATE_0_REPOSITORY_AUDIT','GATE_1_INITIALIZATION','GATE_2_DATA_AND_OVERLAP',...
    'GATE_3_PARTITION','GATE_4_PREPROCESSING','GATE_5_FEATURE_SELECTION',...
    'GATE_6_HYPERPARAMETER_TUNING','GATE_7_OOF_AND_BASE_MODELS','GATE_8_META_LEARNERS',...
    'GATE_9_ABLATION','GATE_10_MULTISEED','GATE_11_FROZEN_DEPLOYMENT',...
    'GATE_12_BLIND_EVALUATION','GATE_13_GEOMECHANICS','GATE_14_NUMERICAL_FREEZE',...
    'GATE_15_CROSS_RUN_REPRODUCIBILITY','GATE_16_PUBLICATION_REPORTING'};
run.gate = struct();
for gi = 1:numel(gates)
    run.gate.(gates{gi}) = 'PENDING';
end

% Gate 0 must be set by the caller after audit
% Gate 1: this function completes initialization
run.gate.GATE_1_INITIALIZATION = 'PASS';

run_log(run, sprintf('GATE_1_INITIALIZATION = PASS'));
fprintf('  [INIT] RUN_ID = %s\n', run.id);
fprintf('  [INIT] Folder: %s\n', run.folder);
fprintf('  [INIT] GATE_1_INITIALIZATION = PASS\n');
end

function run_log(run, msg)
if isfield(run,'log_fid') && run.log_fid > 0
    fprintf(run.log_fid,'[%s] %s\n', datestr(now,'HH:MM:SS.FFF'), msg); %#ok<DATST>
end
fprintf('  %s\n', msg);
end
