function generate_all(run_folder, varargin)
% GSE_REPORT.GENERATE_ALL  Publication reporting pipeline (Gate 16).
%
%  Reads from FROZEN_NUMERICAL_RUN.mat — NEVER retrains, never recomputes.
%  All figures read metrics from run struct. No hard-coded values.
%  Output → run_folder/publication_reporting/
%
%  Usage:
%    gse_report.generate_all(run_folder)
%    gse_report.generate_all(run_folder, 'FIG03')
%    gse_report.generate_all(run_folder, {'FIG01','FIG06'})
%    gse_report.generate_all(run_folder, 'force', true)

narginchk(1, Inf);

%% Parse optional args
fig_list = {}; force = false;
for ii = 1:numel(varargin)
    a = varargin{ii};
    if ischar(a) && strcmpi(a,'force') && ii < numel(varargin)
        force = logical(varargin{ii+1});
    elseif ischar(a) && numel(a)>=4 && startsWith(upper(a),'FIG')
        fig_list = {upper(a)};
    elseif iscell(a)
        fig_list = cellfun(@upper, a, 'UniformOutput', false);
    end
end

fprintf('\n%s\n', repmat('=',1,65));
fprintf('  GSE_REPORT | Gate 16 — Publication Reporting\n');
fprintf('  Run: %s\n', run_folder);
fprintf('%s\n\n', repmat('=',1,65));

%% Load frozen run (read-only)
bundle = gse_report.load_frozen_run(run_folder);

%% Validate
gse_report.validate_frozen_run(bundle);

%% Create output folder (NEW — never overwrites results/)
out_root = fullfile(run_folder, 'publication_reporting');
subdirs = {'figures_main','figures_supplementary','figures_preview',...
           'figures_source_data','graphical_abstract'};
for si = 1:numel(subdirs)
    d = fullfile(out_root, subdirs{si});
    if ~isfolder(d); mkdir(d); end
end
bundle.out = out_root;
bundle.cfg_fig = make_fig_cfg(bundle.run.cfg);

%% Build model registry (single lookup for all figures)
bundle.registry = gse_report.build_model_registry(bundle);

%% Resolve figure list
all_figs = {'FIG01','FIG02','FIG03','FIG04','FIG05','FIG06','FIG07','FIG08'};
if isempty(fig_list); fig_list = all_figs; end

%% Generate each figure
fig_status = containers.Map(all_figs, repmat({'NOT_REQUESTED'},1,8));
n_pass = 0; n_fail = 0;
for fi = 1:numel(fig_list)
    fid = fig_list{fi};
    tif = fullfile(out_root,'figures_main',[fig_id_to_filename(fid) '.TIF']);
    if isfile(tif) && ~force
        fprintf('  [SKIP] %s (exists — use force=true to regenerate)\n', fid);
        fig_status(fid) = 'PASS'; n_pass=n_pass+1; continue;
    end
    try
        ei = gse_report.generate_one(fid, bundle);
        fig_status(fid) = ei.status;
        if strcmp(ei.status,'PASS'); n_pass=n_pass+1; else; n_fail=n_fail+1; end
    catch ME
        fprintf('  [FAIL] %s: %s\n', fid, ME.message);
        fig_status(fid) = 'FAIL'; n_fail=n_fail+1;
    end
end

%% Graphical abstract
try
    gse_report.make_graphical_abstract(bundle);
catch ME
    fprintf('  [WARN] GA: %s\n', ME.message);
end

%% Supplementary figures
try
    gse_report.make_supplementary(bundle);
catch ME
    fprintf('  [WARN] Supplementary: %s\n', ME.message);
end

%% Captions, manifest, QC
gse_report.generate_captions(bundle, fig_status);
gse_report.generate_manifest(bundle, fig_status);
all_pass = gse_report.run_qc(bundle, fig_status);

%% Summary
fprintf('\n%s\n', repmat('=',1,65));
if all_pass && n_fail == 0
    fprintf('  GATE_16 = PASS — REPORTING PIPELINE COMPLETE\n');
    fprintf('  %d main figures | Output: %s\n', n_pass, out_root);
else
    fprintf('  GATE_16 = FAIL — %d figure(s) failed\n', n_fail);
    error('Reporting:Incomplete','%d main figure(s) failed. Numerical results unchanged.', n_fail);
end
fprintf('%s\n\n', repmat('=',1,65));

% Write Gate 16 status
fid_g = fopen(fullfile(out_root,'GATE16_STATUS.txt'),'w');
fprintf(fid_g,'GATE_16 = %s\n', char('PASS'*(n_fail==0)+'FAIL'*(n_fail>0)));
fprintf(fid_g,'n_pass = %d\nn_fail = %d\n', n_pass, n_fail);
fprintf(fid_g,'run_id = %s\n', bundle.run.id);
fclose(fid_g);
end

% ─────────────────────────────────────────────────────────────────────────────
function fname = fig_id_to_filename(fid)
map = struct(...
    'FIG01','FIG01_study_design_and_validation',...
    'FIG02','FIG02_well_logs_and_qc',...
    'FIG03','FIG03_domain_shift',...
    'FIG04','FIG04_model_development_and_selection',...
    'FIG05','FIG05_multiseed_and_consistency',...
    'FIG06','FIG06_blind_well_evaluation',...
    'FIG07','FIG07_cross_domain_diagnostics',...
    'FIG08','FIG08_geomechanical_consequences');
safe = matlab.lang.makeValidName(fid);
if isfield(map, safe); fname = map.(safe); else; fname = fid; end
end

function cfg_fig = make_fig_cfg(cfg)
cfg_fig = cfg.output;
cfg_fig.color_A    = cfg.output.color_A;
cfg_fig.color_B    = cfg.output.color_B;
cfg_fig.color_dep  = cfg.output.color_deploy;
cfg_fig.color_emp  = cfg.output.color_emp;
cfg_fig.color_fail = [0.8 0.1 0.1];
cfg_fig.color_dup  = cfg.output.color_dup;
cfg_fig.width_in   = cfg.output.width_in;
cfg_fig.max_h_in   = cfg.output.max_h_in;
end
