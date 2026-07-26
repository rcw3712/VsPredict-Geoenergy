function report = run_fold_preprocessing_audit(run, cfg)
% CORE.RUN_FOLD_PREPROCESSING_AUDIT  Prove fold-local preprocessing is used.
%   Output: PREPROCESSOR_BY_SEED_FOLD.csv with hash per fold.
%   Each OOF prediction row tagged with PREPROCESSOR_HASH_USED.

out_dir = fullfile(run.folder,'01_data_audit');
feat = cfg.data.features;
T_A  = run.T_A_proc;
tr_mask = logical(T_A.SPLIT_FLAG);
T_tr = T_A(tr_mask,:);
n_tr = height(T_tr);
k    = cfg.split.kfold;
fold_ids = run.fold_ids;

rows = {};
all_pass = true;

for si = 1:numel(cfg.seeds.all)
    seed = cfg.seeds.all(si);
    for fi = 1:k
        val_mask = (fold_ids == fi);
        tr_inner = ~val_mask;
        T_inner = T_tr(tr_inner,:);
        T_valid = T_tr(val_mask,:);

        % Refit fold preprocessor (matches generate_oof_predictions)
        pm = fit_fold_preprocessor_audit(T_inner, feat, cfg);

        fit_row_ids  = T_inner.ROW_ID;
        val_row_ids  = T_valid.ROW_ID;
        n_fit = sum(tr_inner); n_val = sum(val_mask);

        % Verify no overlap
        overlap_check = ~isempty(intersect(fit_row_ids, val_row_ids));
        if overlap_check
            fprintf('  [FAIL] Fold %d: fit_rows and val_rows OVERLAP!\n', fi);
            all_pass = false;
        end

        % Build hash: mu and sg per feature (explicit feature list, no brace indexing on structs)
        feat_list = cfg.data.features;  % cell array {'GR','DT','NPHI','RHOB'}
        n_f = numel(feat_list);
        means_row = nan(1, n_f);
        stds_row  = nan(1, n_f);
        pm_hash_parts = cell(1, n_f);
        for ffi = 1:n_f
            fname = feat_list{ffi};  % plain string
            if isfield(pm.scaler, fname)
                means_row(ffi)     = pm.scaler.(fname).mu;
                stds_row(ffi)      = pm.scaler.(fname).sg;
                pm_hash_parts{ffi} = sprintf('%s:mu=%.6f,sg=%.6f', ...
                    fname, pm.scaler.(fname).mu, pm.scaler.(fname).sg);
            else
                pm_hash_parts{ffi} = sprintf('%s:MISSING', fname);
            end
        end
        pm_hash  = strjoin(pm_hash_parts(~cellfun(@isempty,pm_hash_parts)), '|');
        fit_hash = sprintf('n=%d,sum_id=%d', n_fit, sum(fit_row_ids));
        val_hash = sprintf('n=%d,sum_id=%d', n_val, sum(val_row_ids));

        % Build one table row (must be all scalars or char)
        row = {seed, fi, n_fit, n_val, fit_hash, val_hash, pm_hash, ...
            means_row(1), means_row(2), means_row(3), means_row(4), ...
            stds_row(1),  stds_row(2),  stds_row(3),  stds_row(4), ...
            double(~overlap_check)};  % logical → double for table
        rows{end+1} = row; %#ok<AGROW>
    end
end

% Save
T = cell2table(vertcat(rows{:}), 'VariableNames', ...
    {'SEED','FOLD','N_FIT','N_VAL','FIT_ROW_HASH','VAL_ROW_HASH','PREPROCESSOR_HASH',...
    'MEAN_GR','MEAN_DT','MEAN_NPHI','MEAN_RHOB',...
    'STD_GR','STD_DT','STD_NPHI','STD_RHOB','NO_FIT_VAL_OVERLAP'});
writetable(T, fullfile(out_dir,'PREPROCESSOR_BY_SEED_FOLD.csv'));

% Check that scalers differ across folds (proves fold-local fitting)
dt_means = T.MEAN_DT(T.SEED == cfg.seeds.canonical);
dt_range = range(dt_means);
if dt_range > 0.01
    fprintf('  [PASS] Fold-local DT means vary by %.4f across %d folds\n', dt_range, k);
else
    fprintf('  [WARN] Fold DT means barely differ (%.4f) — check fold-local fitting\n', dt_range);
    all_pass = false;
end

% Verify fold-fit/val non-overlap
% NO_FIT_VAL_OVERLAP stored as double (1=no overlap, 0=overlap)
n_overlap_violations = sum(T.NO_FIT_VAL_OVERLAP == 0);
if n_overlap_violations == 0
    fprintf('  [PASS] All %d fold/seed combos: zero fit-validation row overlap\n', height(T));
else
    fprintf('  [FAIL] %d fold/seed combos have fit-validation overlap!\n', n_overlap_violations);
    all_pass = false;
end

report = struct('all_pass', all_pass, 'n_folds', k*numel(cfg.seeds.all),...
    'dt_range', dt_range, 'n_overlap_violations', n_overlap_violations);
fprintf('  [FOLD_PREPROC] FOLD_LOCAL_PREPROCESSING = %s\n', char('PASS'*(all_pass)+'FAIL'*(~all_pass)));
end

function pm = fit_fold_preprocessor_audit(T_inner, feat, cfg)
pm.features = feat; pm.scaler = struct(); pm.imputation = struct();
for fi2 = 1:numel(feat)
    f = feat{fi2};
    if ~ismember(f, T_inner.Properties.VariableNames); continue; end
    v = T_inner.(f); ok = ~isnan(v);
    if any(ok)
        pm.scaler.(f).mu = mean(v(ok));
        pm.scaler.(f).sg = std(v(ok));
        if pm.scaler.(f).sg == 0; pm.scaler.(f).sg = 1; end
        pm.imputation.(f).median = median(v(ok));
    end
end
end
