function registry = build_model_registry(bundle)
% GSE_REPORT.BUILD_MODEL_REGISTRY  Single lookup for all models.
%   All metric values read from run struct — no hard-coding.
%   Empirical predictions computed once here from raw VP.

run = bundle.run;
cfg_fig = bundle.cfg_fig;

% Empirical constants (physical, not results — these are known equations)
C_CAST  = [0.8042, -0.8559];  % Castagna mudrock
C_SHALE = [0.7700, -0.8674];  % GC shale
C_SAND  = [0.7936, -0.7868];  % GC sand
C_LIME  = [-0.05509, 1.0168, -1.0305];  % GC limestone

% Get Well-B Seg0 raw VP/VS for empirical predictions
T_B = run.T_B_raw;
seg0 = T_B.DEPTH <= run.cfg.depth.wellB_seg0_max;
vp_seg0 = T_B.VP(seg0);
vs_seg0 = T_B.VS(seg0);
n_seg0  = sum(seg0);

emp_pred = struct(...
    'Castagna_mudrock', C_CAST(1)*vp_seg0  + C_CAST(2), ...
    'GC_shale',         C_SHALE(1)*vp_seg0 + C_SHALE(2), ...
    'GC_sand',          C_SAND(1)*vp_seg0  + C_SAND(2), ...
    'GC_limestone',     C_LIME(1)*vp_seg0.^2 + C_LIME(2)*vp_seg0 + C_LIME(3));

% Training-mean baseline (from Well-A training block, NOT from any prediction)
T_A = run.T_A_raw;
tr_vs = T_A.VS(T_A.DEPTH <= run.cfg.depth.wellB_seg0_max - ...
    (run.cfg.depth.wellB_seg0_max - min(T_A.DEPTH)) * run.cfg.split.test_frac);
train_mean_vs = mean(T_A.VS(1:run.n_train),'omitnan');

% ML predictions from predictions_WellB_v4.csv (authoritative)
pred_csv = bundle.pred_csv;
ml_preds = struct();
if ~isempty(pred_csv) && height(pred_csv)>0
    ml_preds.ridge = pred_csv.VS_pred_raw;
end
% All-model predictions from PREDICTIONS_WELLB_ALL_MODELS.csv
allmodel_path = fullfile(bundle.run_folder,'06_predictions','PREDICTIONS_WELLB_ALL_MODELS.csv');
if isfile(allmodel_path)
    T_all = readtable(allmodel_path,'VariableNamingRule','preserve');
    all_model_cols = setdiff(T_all.Properties.VariableNames,...
        {'ROW_ID','DEPTH','VS_measured','POP_A_MASK','POP_B_MASK'},'stable');
    for aci=1:numel(all_model_cols)
        nm_ac = all_model_cols{aci};
        nm_safe = matlab.lang.makeValidName(nm_ac);
        ml_preds.(nm_safe) = T_all.(nm_ac);
    end
    fprintf('[GSE] Loaded %d model predictions from PREDICTIONS_WELLB_ALL_MODELS.csv\n',...
        numel(all_model_cols));
end

% All model names
all_names = {'pnn','mlffnn','dffnn','cnn1d','ridge_stacker','icnn','hybrid_icnn',...
             'training_mean','Castagna_mudrock','GC_shale','GC_sand','GC_limestone'};
disp_names = {'PNN','MLFFNN','DFFNN','CNN1D','Ridge stacker','I-CNN','Hybrid I-CNN',...
              'Training mean (Well-A)','Castagna mudrock','GC shale','GC sand','GC limestone'};
types = {'base','base','base','base','meta','meta','meta','baseline',...
         'empirical','empirical','empirical','empirical'};

% Post-hoc best: find highest R² on Pop-B from stored metrics
% (all stored in run.eval_popB or computed from empirical vs vs_seg0)
popB_mask = logical(T_B.POP_B_PHYSICAL_QC(seg0));
vs_true_popB = vs_seg0(popB_mask);

best_blind_r2 = -Inf; best_blind_name = '';

registry = struct('name',{},'display_name',{},'model_type',{},...
    'prediction_raw',{},'r2_wellA',{},'r2_popA',{},'r2_popB',{},...
    'rmse_popB',{},'bias_popB',{},'n_popB',{},...
    'is_deployed',{},'is_posthoc_best',{});

for ni = 1:numel(all_names)
    nm = all_names{ni};

    % Clear e completely each iteration — prevents field accumulation across iterations
    e = struct();

    % ── Mandatory schema fields (must ALL be set in every iteration) ──────────
    e.name            = nm;
    e.display_name    = disp_names{ni};
    e.model_type      = types{ni};
    e.prediction_raw  = [];
    e.r2_wellA        = NaN;
    e.r2_popA         = NaN;
    e.r2_popB         = NaN;
    e.rmse_popB       = NaN;
    e.bias_popB       = NaN;
    e.n_popB          = sum(popB_mask);
    e.is_deployed     = false;
    e.is_posthoc_best = false;

    % ── Prediction series (Seg0, 329 rows) ────────────────────────────────────
    nm_safe = matlab.lang.makeValidName(nm);
    if isfield(emp_pred, nm_safe)
        e.prediction_raw = emp_pred.(nm_safe);
    elseif strcmp(nm,'training_mean')
        e.prediction_raw = repmat(train_mean_vs, n_seg0, 1);
    elseif strcmp(nm,'ridge_stacker') && isfield(ml_preds,'ridge')
        e.prediction_raw = ml_preds.ridge(seg0);
    end

    % ── Compute Pop-B metrics from predictions ────────────────────────────────
    if ~isempty(e.prediction_raw)
        yp = e.prediction_raw(popB_mask);
        ok = ~isnan(vs_true_popB) & ~isnan(yp);
        yt = vs_true_popB(ok); yh = yp(ok);
        if sum(ok) > 2
            ss_tot      = sum((yt - mean(yt)).^2);
            e.r2_popB   = 1 - sum((yt-yh).^2) / ss_tot;
            e.rmse_popB = sqrt(mean((yt-yh).^2));
            e.bias_popB = mean(yh - yt);
        end
    end

    % ── Override with authoritative run struct values where available ──────────
    if strcmp(nm, 'ridge_stacker')
        e.r2_wellA  = run.deploy_r2_WA;
        e.r2_popA   = run.eval_popA.R2_raw;
        e.r2_popB   = run.eval_popB.R2_raw;    % exact value from eval
        e.rmse_popB = run.eval_popB.RMSE_raw;
        e.bias_popB = run.eval_popB.bias_raw;
    else
        % Other meta-learners: Well-A test R² from meta_metrics if available
        mm_key = strrep(nm, '_stacker', '');
        if isfield(run, 'meta_metrics') && isfield(run.meta_metrics, mm_key)
            e.r2_wellA = run.meta_metrics.(mm_key).R2_te;
        end
    end

    % ── Deployment flag ───────────────────────────────────────────────────────
    e.is_deployed = strcmp(nm, run.deploy_name);

    % ── Track post-hoc best on Pop-B ─────────────────────────────────────────
    if ~isnan(e.r2_popB) && e.r2_popB > best_blind_r2
        best_blind_r2   = e.r2_popB;
        best_blind_name = nm;
    end

    registry(ni) = e;
end

% Mark post-hoc best
for ni = 1:numel(registry)
    registry(ni).is_posthoc_best = strcmp(registry(ni).name, best_blind_name);
end

fprintf('[GSE] Registry: %d models | deploy=%s | posthoc_best=%s (R²=%.4f)\n', ...
    numel(registry), run.deploy_name, best_blind_name, best_blind_r2);
end
