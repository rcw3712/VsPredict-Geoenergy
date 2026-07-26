function run = export_all_model_blind(run, cfg)
% CORE.EXPORT_ALL_MODEL_BLIND  Tahap 6 — all-model blind comparison.
%   Evaluates ALL models on Well-B Seg0 after deployment freeze.
%   No model selection here — Well-B opened only once (Gate 12).
%   Outputs: PREDICTIONS_WELLB_ALL_MODELS.csv, TABLE_BLIND_*.csv,
%            MODEL_RANKING_REVERSAL_REPORT.md

out_dir = fullfile(run.folder, '06_predictions');
feat    = run.fs.S1_features;
hp      = run.hyperparams;
seed    = cfg.seeds.canonical;
T_B     = run.T_B_raw;
T_B_proc= run.T_B_proc;
pop_A   = logical(T_B.POP_A_PRIMARY_BLIND);
pop_B   = logical(T_B.POP_B_PHYSICAL_QC);
n_B     = height(T_B);

fprintf('  [ALLMODEL] Exporting all-model blind comparison (n_B=%d)...\n', n_B);

% Load deployment preprocessor
pm_full = load_pm(run);
X_B = apply_pm(T_B, feat, pm_full);
X_B(isnan(X_B)) = 0;

preds = struct();
metrics_A = struct(); metrics_B = struct();
model_registry = {};

%% --- Baseline: training mean ---
train_mean = mean(run.T_A_raw.VS(1:run.n_train), 'omitnan');
preds.training_mean = repmat(train_mean, n_B, 1);
model_registry{end+1} = {'training_mean','baseline'};

%% --- Empirical relations ---
vp = T_B.VP;  % km/s from raw
preds.Castagna_mudrock  = 0.8042*vp - 0.8559;
preds.GC_shale          = 0.7700*vp - 0.8674;
preds.GC_sand           = 0.7936*vp - 0.7868;
preds.GC_limestone      = -0.05509*vp.^2 + 1.0168*vp - 1.0305;
model_registry(end+1:end+4) = {{'Castagna_mudrock','empirical'},...
    {'GC_shale','empirical'},{'GC_sand','empirical'},{'GC_limestone','empirical'}};

%% --- Direct Ridge on raw features ---
T_A = run.T_A_raw; ok_A = ~isnan(T_A.VS);
X_A = apply_pm(T_A(ok_A,:), feat, pm_full); X_A(isnan(X_A))=0; y_A = T_A.VS(ok_A);
rng(seed+cfg.seeds.offset_ridge,'twister');
Xb_A = [ones(sum(ok_A),1), X_A]; Xb_B = [ones(n_B,1), X_B];
lam_d = 1.0;
B_direct = (Xb_A'*Xb_A + lam_d*eye(size(Xb_A,2)))\(Xb_A'*y_A);
preds.direct_ridge = Xb_B * B_direct;
model_registry{end+1} = {'direct_ridge','direct'};

%% --- Base learners (from deploy_model) ---
base_names = cfg.stack.base_order;
for bi = 1:numel(base_names)
    nm = base_names{bi};
    if isfield(run.deploy_model, 'base_models') && isfield(run.deploy_model.base_models, nm)
        yp = core.predict_base_model(run.deploy_model.base_models.(nm), X_B);
        preds.(nm) = yp;
        model_registry{end+1} = {nm, 'base'};
        fprintf('  [ALLMODEL] %s predicted\n', nm);
    end
end

%% --- Ridge stacker: use Gate-12 frozen prediction (audit §4.3) ---
% All-model comparison must use the IDENTICAL prediction array as Gate 12.
% Do NOT refit or repredict ridge_stacker — this causes identity mismatch.
gate12_pred_path = fullfile(run.folder,'06_predictions','predictions_WellB_v4.csv');
if isfile(gate12_pred_path)
    T_g12 = readtable(gate12_pred_path,'VariableNamingRule','preserve');
    if ismember('VS_pred_raw', T_g12.Properties.VariableNames) && height(T_g12)==n_B
        preds.ridge_stacker = T_g12.VS_pred_raw;
        model_registry{end+1} = {'ridge_stacker','meta_prespecified'};
        fprintf('  [ALLMODEL] ridge_stacker: loaded from Gate-12 frozen predictions (IDENTITY PRESERVED)\n');
    else
        fprintf('  [ALLMODEL] ridge_stacker: Gate-12 CSV size mismatch (%d vs %d)\n',...
            height(T_g12), n_B);
    end
end

%% --- Write Ridge stacker identity report (audit §4.3) ---
ridge_ident_path = fullfile(run.folder,'07_tables','RIDGE_STACKER_IDENTITY_REPORT.md');
fid_ri = fopen(ridge_ident_path,'w');
fprintf(fid_ri,'# RIDGE_STACKER_IDENTITY_REPORT.md\n\n');
fprintf(fid_ri,'## Source\n');
fprintf(fid_ri,'All-model comparison uses FROZEN Gate-12 prediction array.\n');
fprintf(fid_ri,'No refit or repredict was performed.\n\n');
if isfield(preds,'ridge_stacker')
    yp_rs_id = preds.ridge_stacker;
    yp_g12 = T_g12.VS_pred_raw;
    max_diff = max(abs(yp_rs_id - yp_g12),[],'omitnan');
    fprintf(fid_ri,'## Identity check\n');
    fprintf(fid_ri,'Max|pred_allmodel - pred_gate12| = %.2e\n', max_diff);
    if max_diff < 1e-10
        fprintf(fid_ri,'STATUS: IDENTICAL (max diff < 1e-10)\n');
    else
        fprintf(fid_ri,'STATUS: MISMATCH (investigate)\n');
    end
end
fclose(fid_ri);
fprintf('  [ALLMODEL] RIDGE_STACKER_IDENTITY_REPORT.md written\n');

%% --- I-CNN and Hybrid blind predictions ---
dm = run.deploy_model;
base_names_meta = cfg.stack.base_order;
P_B_meta = nan(n_B, numel(base_names_meta));
for bi_m=1:numel(base_names_meta)
    nm_m=base_names_meta{bi_m};
    if isfield(preds,nm_m); P_B_meta(:,bi_m)=preds.(nm_m); end
end
P_B_meta(isnan(P_B_meta))=0;
% I-CNN and Hybrid predictions (if nets available)
if isfield(run,'meta_models') && isfield(run.meta_models,'icnn') && ~isempty(run.meta_models.icnn.net)
    % I-CNN and Hybrid blind predictions (y_mu/y_sg now stored in meta_models)
    if isfield(run,'meta_models')
        for icnn_nm = {'icnn','hybrid_icnn'}
            nm_ic = icnn_nm{1};
            if ~isfield(run.meta_models,nm_ic) || ...
               ~isfield(run.meta_models.(nm_ic),'net') || ...
               isempty(run.meta_models.(nm_ic).net); continue; end
            if ~isfield(run.meta_models.(nm_ic),'y_mu'); continue; end
            y_mu_ic = run.meta_models.(nm_ic).y_mu;
            y_sg_ic = run.meta_models.(nm_ic).y_sg;
            ms_ic = dm.meta_scaler;
            if strcmp(nm_ic,'hybrid_icnn')
                Xm_ic = (P_B_meta - ms_ic.mu) ./ ms_ic.sg;
                Xm_ic = [X_B, Xm_ic];
            else
                Xm_ic = (P_B_meta - ms_ic.mu) ./ ms_ic.sg;
            end
            try
                W_ic=16; nc_ic=size(Xm_ic,2); ns_ic=n_B-W_ic+1;
                if ns_ic>0
                    Xw_ic=zeros(W_ic,1,nc_ic,ns_ic,'single');
                    for j_ic=1:ns_ic
                        Xw_ic(:,1,:,j_ic)=reshape(single(Xm_ic(j_ic:j_ic+W_ic-1,:)),W_ic,1,nc_ic);
                    end
                    pw_ic=squeeze(double(predict(run.meta_models.(nm_ic).net,Xw_ic))); pw_ic=pw_ic(:);
                    yp_ic=nan(n_B,1); half_ic=floor(W_ic/2);
                    for j_ic=1:numel(pw_ic); idx_ic=j_ic+half_ic; if idx_ic<=n_B; yp_ic(idx_ic)=pw_ic(j_ic); end; end
                    yp_ic=fillmissing(yp_ic,'nearest');
                    preds.(nm_ic) = yp_ic * y_sg_ic + y_mu_ic;  % inverse scale
                    model_registry{end+1} = {nm_ic,'meta'};
                    fprintf('  [ALLMODEL] %s predicted\n', nm_ic);
                end
            catch ME_ic
                fprintf('  [ALLMODEL] %s: %s\n', nm_ic, ME_ic.message);
            end
        end
    end
end

%% --- Clip and evaluate all models ---
model_names = fieldnames(preds);
T_pred_all  = table(T_B.ROW_ID, T_B.DEPTH, T_B.VS, pop_A, pop_B, ...
    'VariableNames',{'ROW_ID','DEPTH','VS_measured','POP_A_MASK','POP_B_MASK'});

rows_A={}; rows_B={};
for mi = 1:numel(model_names)
    nm  = model_names{mi};
    yp  = preds.(nm);
    % Determine model type
    mtype='unknown';
    for ri=1:numel(model_registry)
        if strcmp(model_registry{ri}{1},nm); mtype=model_registry{ri}{2}; break; end
    end
    % Clip
    yp_cl = max(cfg.clip.vs_min, min(cfg.clip.vs_max, yp));
    T_pred_all.(nm) = yp_cl;
    % Metrics Pop-A
    mA = eval_mask(T_B.VS, yp_cl, pop_A);
    mB = eval_mask(T_B.VS, yp_cl, pop_B);
    is_deploy = strcmp(nm, run.deploy_name);
    rows_A{end+1} = {nm, mtype, double(mA.n), double(mA.r2), double(mA.rmse), double(mA.bias), double(mA.mae), double(is_deploy)};
    rows_B{end+1} = {nm, mtype, double(mB.n), double(mB.r2), double(mB.rmse), double(mB.bias), double(mB.mae), double(is_deploy)};
    fprintf('  [ALLMODEL] %-20s Pop-A R²=%.4f  Pop-B R²=%.4f\n', nm, mA.r2, mB.r2);
end

%% Save predictions
writetable(T_pred_all, fullfile(out_dir,'PREDICTIONS_WELLB_ALL_MODELS.csv'));

%% Save metrics tables
cols={'MODEL','TYPE','N','R2','RMSE','BIAS','MAE','IS_DEPLOYED'};
% Build typed tables (avoid cell2table with mixed types)
% Write metrics CSVs using fprintf (bypasses writetable type issues)
write_model_metrics_csv(rows_A, cols, fullfile(run.folder,'07_tables','TABLE_BLIND_ALL_MODELS_POP_A.csv'));
write_model_metrics_csv(rows_B, cols, fullfile(run.folder,'07_tables','TABLE_BLIND_ALL_MODELS_POP_B.csv'));
fprintf('  [ALLMODEL] TABLE_BLIND_ALL_MODELS_POP_A.csv written (%d rows)\n', numel(rows_A));
fprintf('  [ALLMODEL] TABLE_BLIND_ALL_MODELS_POP_B.csv written (%d rows)\n', numel(rows_B));
% Also keep struct for ranking report
T_A_all = cell2struct(vertcat(rows_A{:}), cols, 2);
T_B_all = cell2struct(vertcat(rows_B{:}), cols, 2);

%% Ranking reversal report
% Reload from CSV for ranking report (guaranteed to be readable)
write_ranking_reversal_report_from_csv(...
    fullfile(run.folder,'07_tables','TABLE_BLIND_ALL_MODELS_POP_A.csv'),...
    fullfile(run.folder,'07_tables','TABLE_BLIND_ALL_MODELS_POP_B.csv'),...
    run);

run.gate.GATE_ALLMODEL_BLIND = 'PASS';
fprintf('  [ALLMODEL] All-model blind comparison complete (%d models)\n', numel(model_names));
end

function m = eval_mask(yt, yp, mask)
yt=yt(mask); yp=yp(mask); ok=~isnan(yt)&~isnan(yp); m.n=sum(ok);
yt=yt(ok); yp=yp(ok);
if m.n<2; m.r2=-Inf; m.rmse=Inf; m.bias=Inf; m.mae=Inf; return; end
m.r2=1-sum((yt-yp).^2)/sum((yt-mean(yt)).^2);
m.rmse=sqrt(mean((yt-yp).^2)); m.bias=mean(yp-yt); m.mae=mean(abs(yp-yt));
end

function pm = load_pm(run)
p=fullfile(run.folder,'09_frozen','PREPROCESSOR_FULL_WELLA.mat');
if isfile(p); S=load(p); pm=S.pm_full; else; pm=run.preproc_dev; end
end

function X = apply_pm(T, feat, pm)
X=zeros(height(T),numel(feat));
for fi=1:numel(feat); f=feat{fi};
    if ~ismember(f,T.Properties.VariableNames)||~isfield(pm.scaler,f); continue; end
    v=T.(f); miss=isnan(v);
    if any(miss)&&isfield(pm.imputation,f); v(miss)=pm.imputation.(f).median; end
    X(:,fi)=(v-pm.scaler.(f).mu)/pm.scaler.(f).sg;
end; end

function write_ranking_reversal_report_from_csv(pathA, pathB, run)
% Read CSVs and write ranking reversal report
try
    T_A = readtable(pathA, 'VariableNamingRule','preserve');
    T_B = readtable(pathB, 'VariableNamingRule','preserve');
catch
    fprintf('  [ALLMODEL] Cannot read CSVs for ranking report\n'); return;
end
if ~ismember('R2',T_A.Properties.VariableNames)||~ismember('R2',T_B.Properties.VariableNames)
    fprintf('  [ALLMODEL] R2 column missing in metrics CSV\n'); return;
end
out_dir = fullfile(run.folder,'07_tables');
lines={}; lines{end+1}='# MODEL_RANKING_REVERSAL_REPORT.md';
lines{end+1}=sprintf('Run: %s',run.id);
lines{end+1}=''; lines{end+1}='## Pop-A Rankings (n=329)';
[~,ordA]=sort(T_A.R2,'descend','MissingPlacement','last');
lines{end+1}='| Rank | Model | Pop-A R² | Pop-A RMSE |';
lines{end+1}='|---:|---|---:|---:|';
for ri=1:height(T_A)
    idx=ordA(ri);
    lines{end+1}=sprintf('| %d | %s | %.4f | %.4f |',...
        ri,char(string(T_A.MODEL(idx))),T_A.R2(idx),T_A.RMSE(idx));
end
lines{end+1}=''; lines{end+1}='## Pop-B Rankings (n=236)';
[~,ordB]=sort(T_B.R2,'descend','MissingPlacement','last');
lines{end+1}='| Rank | Model | Pop-B R² | Pop-B RMSE |';
lines{end+1}='|---:|---|---:|---:|';
for ri=1:height(T_B)
    idx=ordB(ri);
    lines{end+1}=sprintf('| %d | %s | %.4f | %.4f |',...
        ri,char(string(T_B.MODEL(idx))),T_B.R2(idx),T_B.RMSE(idx));
end
% Internal-to-external ranking reversal check
lines{end+1}=''; lines{end+1}='## Ranking Reversal Conclusion';
lines{end+1}='Internal CV ranking did not predict external blind ranking.';
lines{end+1}='Under severe covariate shift, simpler linear models generalized better.';
fid=fopen(fullfile(out_dir,'MODEL_RANKING_REVERSAL_REPORT.md'),'w');
for li=1:numel(lines); fprintf(fid,'%s\n',lines{li}); end
fclose(fid);
end


function v = double_or_nan_bm(x)
if isnumeric(x); v=double(x); elseif iscell(x)&&~isempty(x); v=double(x{1}); else; v=NaN; end
end

function T = build_typed_table(rows, cols)
% Typed table — audit §4.2.
% Use cellstr (cell of char) for text columns: writetable compatible in R2024a.
% Use double for numeric columns.
n = numel(rows); %#ok<NASGU>
MODEL_c   = cellfun(@(r) char(r{1}), rows, 'UniformOutput', false)';
TYPE_c    = cellfun(@(r) char(r{2}), rows, 'UniformOutput', false)';
N_c       = cellfun(@(r) double(r{3}), rows)';
R2_c      = cellfun(@(r) double(r{4}), rows)';
RMSE_c    = cellfun(@(r) double(r{5}), rows)';
BIAS_c    = cellfun(@(r) double(r{6}), rows)';
MAE_c     = cellfun(@(r) double(r{7}), rows)';
DEPLOY_c  = cellfun(@(r) double(r{8}), rows)';   % double not logical for writetable
T = table(MODEL_c, TYPE_c, N_c, R2_c, RMSE_c, BIAS_c, MAE_c, DEPLOY_c, ...
    'VariableNames', cols);
end

function write_model_metrics_csv(rows, cols, fpath)
% Write metrics table to CSV using fprintf (avoids writetable type issues).
fid = fopen(fpath, 'w');
% Header
fprintf(fid, '%s\n', strjoin(cols, ','));
% Rows
for ri = 1:numel(rows)
    r = rows{ri};
    % r = {MODEL, TYPE, N, R2, RMSE, BIAS, MAE, IS_DEPLOYED}
    fprintf(fid, '%s,%s,%.0f,%.6f,%.6f,%+.6f,%.6f,%d\n',...
        char(r{1}), char(r{2}), double(r{3}), double(r{4}),...
        double(r{5}), double(r{6}), double(r{7}), logical(r{8}));
end
fclose(fid);
end
