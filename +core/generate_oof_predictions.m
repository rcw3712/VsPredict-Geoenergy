function run = generate_oof_predictions(run, cfg)
% CORE.GENERATE_OOF_PREDICTIONS  k-fold depth-blocked OOF for base learners.
%   Trains PNN, MLFFNN, DFFNN, CNN1D on k-1 folds; predicts on held-out fold.
%   Uses per-component seeds (Rule §12). Returns OOF predictions for stacking.
%   Rule §11: hyperparameters from run.hyperparams (frozen at Gate 6).

out_dir = fullfile(run.folder,'04_model_development');
feat    = run.fs.S1_features;
hp      = run.hyperparams;
seeds   = cfg.seeds;

T_A    = run.T_A_proc;
tr_mask = logical(T_A.SPLIT_FLAG);
T_tr   = T_A(tr_mask,:);
n_tr   = height(T_tr);
y_tr   = T_tr.VS;
k      = cfg.split.kfold;

% fold_ids indexed by position within training block
fold_ids = run.fold_ids;  % n_tr × 1

base_names = cfg.stack.base_order;  % {'pnn','mlffnn','dffnn','cnn1d'}
n_base = numel(base_names);

% OOF prediction matrix: n_tr × n_base
OOF        = nan(n_tr, n_base);
fold_metrics = struct();

fprintf('  [OOF] %d base learners × %d folds × %d seed(s)\n', n_base, k, numel(seeds.all));

for si = 1:numel(seeds.all)
    seed = seeds.all(si);
    fprintf('  [OOF] Seed %d\n', seed);
    OOF_seed = nan(n_tr, n_base);

    for fi = 1:k
        val_mask = (fold_ids == fi);
        tr_inner = ~val_mask;
        % ── Fold-local preprocessing (Rule §7.1: fit ONLY on inner training folds) ──
        T_inner = T_tr(tr_inner,:);
        T_valid = T_tr(val_mask,:);
        pm_fold = fit_fold_preprocessor(T_inner, feat, cfg);
        [X_in, X_val] = apply_fold_preprocessor(T_inner, T_valid, feat, pm_fold);
        y_val = y_tr(val_mask);
        y_in  = y_tr(tr_inner);

        for bi = 1:n_base
            nm  = base_names{bi};
            off = cfg.seeds.(['offset_' nm]);
            model_seed = seed + off + fi * cfg.seeds.offset_fold_mult;

            hp_b = get_hp(hp, nm);
            rng(model_seed,'twister');
            model  = models.fit_base(X_in, y_in, nm, hp_b, model_seed, cfg);
            y_pred = core.predict_base_model(model, X_val);
            OOF_seed(val_mask, bi) = y_pred;

            r2 = compute_r2(y_val, y_pred);
            fprintf('    Seed%d Fold%d %s: R2=%.4f\n', seed, fi, nm, r2);
            fold_metrics.(sprintf('%s_s%d_f%d',nm,seed,fi)) = struct('R2',r2,'n',sum(val_mask));
        end
    end

    if seed == seeds.canonical
        OOF = OOF_seed;  % canonical seed OOF used for meta-feature
        run.oof_metrics_canonical = fold_metrics;
        run.oof_fold_ids = fold_ids;
    end
    run.(['oof_seed_' num2str(seed)]) = OOF_seed;
end

run.OOF_canonical = OOF;  % n_tr × n_base, canonical seed;  % added semicolon

% Also train base learners on FULL training block for blind prediction
fprintf('  [OOF] Training final base models on full training block...\n');
X_full = table2array(T_tr(:, feat)); X_full(isnan(X_full))=0;
run.base_models_full = struct();
for bi = 1:n_base
    nm  = base_names{bi};
    off = cfg.seeds.(['offset_' nm]);
    rng(seeds.canonical + off + cfg.seeds.offset_refit, 'twister');
    hp_b = get_hp(hp, nm);
    run.base_models_full.(nm) = models.fit_base(X_full, y_tr, nm, hp_b, ...
        seeds.canonical + off + cfg.seeds.offset_refit, cfg);
    fprintf('  [OOF] %s trained on %d rows\n', nm, n_tr);
end

% Save OOF CSV
col_names = strcat(base_names,'_OOF');
T_oof = array2table(OOF,'VariableNames',col_names);
T_oof.DEPTH = T_tr.DEPTH; T_oof.VS_measured = y_tr;
T_oof.FOLD_ID = fold_ids;
writetable(T_oof, fullfile(out_dir,'OOF_predictions_canonical.csv'));

% Save fold metrics CSV
save_fold_metrics(fold_metrics, seeds, k, base_names, out_dir);

run.gate.GATE_7_OOF_AND_BASE_MODELS = 'PASS';
fprintf('  [OOF] GATE_7 = PASS\n');
end

function hp_b = get_hp(hp, nm)
if isfield(hp, nm); hp_b = hp.(nm);
else; hp_b = struct(); end
end

function r2 = compute_r2(yt, yp)
ok = ~isnan(yt) & ~isnan(yp);
yt=yt(ok); yp=yp(ok);
if numel(yt)<2; r2=-Inf; return; end
r2 = 1 - sum((yt-yp).^2)/sum((yt-mean(yt)).^2);
end

function save_fold_metrics(fm, seeds, k, base_names, out_dir)
rows = {}; r2_vals=[]; seed_vals=[]; fold_vals=[]; model_vals={};
fn = fieldnames(fm);
for fi = 1:numel(fn)
    nm = fn{fi};
    parts = strsplit(nm,'_');
    model_vals{end+1} = parts{1}; %#ok<AGROW>
    s_str = parts{2}; seed_vals(end+1) = str2double(s_str(2:end));
    f_str = parts{3}; fold_vals(end+1) = str2double(f_str(2:end));
    r2_vals(end+1) = fm.(nm).R2;
end
T = table(model_vals(:),seed_vals(:),fold_vals(:),r2_vals(:),...
    'VariableNames',{'MODEL','SEED','FOLD','R2_OOF'});
writetable(T, fullfile(out_dir,'OOF_fold_metrics.csv'));
end

% ─── Fold-local preprocessing helpers (Rule §7.1) ────────────────────────────

function pm = fit_fold_preprocessor(T_inner, feat, cfg)
% Fit z-score scaler on inner training folds ONLY — never on validation fold.
pm.features = feat;
pm.scaler   = struct();
pm.imputation = struct();
for fi = 1:numel(feat)
    f = feat{fi};
    if ~ismember(f, T_inner.Properties.VariableNames); continue; end
    v = T_inner.(f);
    ok = ~isnan(v);
    if sum(ok) > 1
        pm.scaler.(f).mu  = mean(v(ok));
        pm.scaler.(f).sg  = std(v(ok));
        if pm.scaler.(f).sg == 0; pm.scaler.(f).sg = 1; end
        pm.imputation.(f).median = median(v(ok));
    end
end
end

function [X_tr, X_val] = apply_fold_preprocessor(T_inner, T_valid, feat, pm)
X_tr  = scale_with_pm(T_inner, feat, pm);
X_val = scale_with_pm(T_valid, feat, pm);
end

function X = scale_with_pm(T, feat, pm)
n = height(T);
X = zeros(n, numel(feat));
for fi = 1:numel(feat)
    f = feat{fi};
    if ~ismember(f, T.Properties.VariableNames); continue; end
    if ~isfield(pm.scaler, f); continue; end
    v = T.(f);
    miss = isnan(v);
    if any(miss) && isfield(pm.imputation, f)
        v(miss) = pm.imputation.(f).median;
    end
    X(:, fi) = (v - pm.scaler.(f).mu) / pm.scaler.(f).sg;
end
end
