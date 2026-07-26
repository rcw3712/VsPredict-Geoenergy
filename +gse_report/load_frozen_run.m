function bundle = load_frozen_run(run_folder)
% GSE_REPORT.LOAD_FROZEN_RUN  Load FROZEN_NUMERICAL_RUN.mat (read-only).
%   Never loads from results/ (old v3 files). Only reads from run_folder/.

fprintf('[GSE] Loading frozen run from: %s\n', run_folder);

mat_path = fullfile(run_folder,'09_frozen','FROZEN_NUMERICAL_RUN.mat');
if ~isfile(mat_path)
    error('gse_report:load','FROZEN_NUMERICAL_RUN.mat not found: %s', mat_path);
end

S = load(mat_path);
fn = fieldnames(S);
% The MAT contains a variable called 'run'
if ismember('run', fn)
    run = S.run;
else
    error('gse_report:load','Expected variable ''run'' in MAT. Found: %s', strjoin(fn,', '));
end

bundle = struct();
bundle.run        = run;
bundle.run_folder = run_folder;

% Load authoritative CSV files (supplement MAT with pre-saved tables)
bundle.pred_csv   = load_csv_safe(run_folder,'06_predictions','predictions_WellB_v4.csv');
bundle.table7A    = load_csv_safe(run_folder,'07_tables','TABLE7A_PopA_allObserved.csv');
bundle.table7B    = load_csv_safe(run_folder,'07_tables','TABLE7B_PopB_physicalQC.csv');
bundle.oof_csv    = load_csv_safe(run_folder,'04_model_development','OOF_predictions_canonical.csv');
bundle.oof_folds  = load_csv_safe(run_folder,'04_model_development','OOF_fold_metrics.csv');
bundle.fs_report  = load_csv_safe(run_folder,'03_feature_selection','FEATURE_SELECTION_REPORT.csv');
bundle.geo_diag   = load_csv_safe(run_folder,'08_geomechanics','geomechanical_diagnostics.csv');
bundle.sel_report = load_csv_safe(run_folder,'04_model_development','MODEL_SELECTION_REPORT.csv');
bundle.masks_csv  = load_csv_safe(run_folder,'01_data_audit','EVALUATION_MASKS.csv');

fprintf('[GSE] Bundle loaded. Run ID: %s\n', run.id);
% Compute domain shift stats from raw data (not hard-coded)
bundle.domain_shift = compute_domain_shift(run);

end

function T = load_csv_safe(base, subdir, fname)
fp = fullfile(base, subdir, fname);
if isfile(fp)
    try
        T = readtable(fp,'VariableNamingRule','preserve');
    catch
        T = readtable(fp);
    end
else
    T = table(); % empty placeholder
    fprintf('[GSE] Note: %s not found (non-critical)\n', fname);
end
end

function ds = compute_domain_shift(run)
% Compute domain shift statistics from raw data — no hard-coded values.
ds = struct();
feat = run.cfg.data.features;
T_A  = run.T_A_raw;
T_B  = run.T_B_raw;
seg0 = T_B.DEPTH <= run.cfg.depth.wellB_seg0_max;
T_B0 = T_B(seg0,:);
n_seg0 = run.n_seg0;
n_popB = run.n_pop_B;
ds.n_qc_flagged = n_seg0 - n_popB;
ds.pct_qc_flagged = ds.n_qc_flagged / n_seg0 * 100;
ds.n_popB = n_popB; ds.n_seg0 = n_seg0;

% Per-feature stats
for fi = 1:numel(feat)
    f = feat{fi};
    if ~ismember(f, T_A.Properties.VariableNames) || ...
       ~ismember(f, T_B0.Properties.VariableNames); continue; end
    va = T_A.(f)(1:run.n_train);  % training block only
    vb = T_B0.(f);
    mu_a = mean(va,'omitnan'); sg_a = std(va,'omitnan');
    mu_b = mean(vb,'omitnan');
    ds.(f).mu_a = mu_a; ds.(f).mu_b = mu_b; ds.(f).sg_a = sg_a;
    ds.(f).z_mu = (mu_b - mu_a) / sg_a;
    ds.(f).delta_pct = (mu_b - mu_a) / abs(mu_a) * 100;
    ds.(f).ood3_pct = sum(abs((vb - mu_a) / sg_a) > 3,'omitnan') / numel(vb) * 100;
end
% Summary for DT (most shifted feature)
if isfield(ds,'DT')
    ds.dt_z = ds.DT.z_mu;
    ds.dt_delta_pct = ds.DT.delta_pct;
    ds.dt_ood3_pct  = ds.DT.ood3_pct;
else
    ds.dt_z = NaN; ds.dt_delta_pct = NaN; ds.dt_ood3_pct = NaN;
end
end
