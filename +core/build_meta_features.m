function run = build_meta_features(run, cfg)
% CORE.BUILD_META_FEATURES  Construct meta-features for stacking.
%   Ridge/I-CNN: [OOF_PNN, OOF_MLFFNN, OOF_DFFNN, OOF_CNN1D]      (4 cols)
%   Hybrid:      [X_raw features, OOF_PNN, OOF_MLFFNN, OOF_DFFNN, OOF_CNN1D] (8 cols)
%   Z-score scaler fitted on OOF training data only (Rule §13).
%   Same scaler applied to test and blind sets.

feat  = run.fs.S1_features;
T_A   = run.T_A_proc;
tr_mask = logical(T_A.SPLIT_FLAG);
T_tr  = T_A(tr_mask,:);
T_te  = T_A(~tr_mask,:);
T_bl  = run.T_B_proc;

OOF   = run.OOF_canonical;        % n_tr × 4, from Gate 7
base_names = cfg.stack.base_order;

% Base model predictions on test and blind sets
fprintf('  [META] Predicting base models on test and blind sets...\n');
X_te  = table2array(T_te(:, feat)); X_te(isnan(X_te))=0;
X_bl_all = table2array(T_bl(:, feat)); X_bl_all(isnan(X_bl_all))=0;
n_base = numel(base_names);
P_te  = nan(height(T_te), n_base);
P_bl  = nan(height(T_bl), n_base);

for bi = 1:n_base
    nm = base_names{bi};
    if isfield(run.base_models_full, nm)
        P_te(:,bi)  = core.predict_base_model(run.base_models_full.(nm), X_te);
        P_bl(:,bi)  = core.predict_base_model(run.base_models_full.(nm), X_bl_all);
        fprintf('  [META] %s predicted on test(%d) blind(%d)\n', nm, height(T_te), height(T_bl));
    else
        fprintf('  [WARN] %s not in base_models_full — using zeros\n', nm);
        P_te(:,bi) = 0; P_bl(:,bi) = 0;
    end
end
P_te(isnan(P_te))=0; P_bl(isnan(P_bl))=0;

% --- Ridge/I-CNN meta-features: OOF predictions only ---
% Scaler fitted on OOF training
oof_mu = mean(OOF,1,'omitnan'); oof_sg = std(OOF,0,1,'omitnan');
oof_sg(oof_sg==0) = 1;
run.meta_scaler_ridge = struct('mu',oof_mu,'sg',oof_sg,'n_cols',n_base,...
    'col_names',{strcat(base_names,'_OOF')},...
    'signature',sprintf('mu_sum=%.6f',sum(oof_mu)));

Xm_tr = (OOF    - oof_mu) ./ oof_sg;
Xm_te = (P_te   - oof_mu) ./ oof_sg;
Xm_bl = (P_bl   - oof_mu) ./ oof_sg;

% --- Hybrid meta-features: raw features + OOF ---
X_tr_raw = table2array(T_tr(:, feat)); X_tr_raw(isnan(X_tr_raw))=0;
hyb_raw = [X_tr_raw, OOF];
hyb_mu  = mean(hyb_raw,1,'omitnan'); hyb_sg = std(hyb_raw,0,1,'omitnan');
hyb_sg(hyb_sg==0)=1;
run.meta_scaler_hybrid = struct('mu',hyb_mu,'sg',hyb_sg,'n_cols',n_base+numel(feat),...
    'signature',sprintf('mu_sum=%.6f',sum(hyb_mu)));

X_te_raw = table2array(T_te(:, feat)); X_te_raw(isnan(X_te_raw))=0;
X_bl_raw = table2array(T_bl(:, feat)); X_bl_raw(isnan(X_bl_raw))=0;

Xm_hyb_tr = ([X_tr_raw, OOF]   - hyb_mu) ./ hyb_sg;
Xm_hyb_te = ([X_te_raw, P_te]  - hyb_mu) ./ hyb_sg;
Xm_hyb_bl = ([X_bl_raw, P_bl]  - hyb_mu) ./ hyb_sg;

% Store
run.meta.Xm_ridge = struct('tr',Xm_tr,'te',Xm_te,'bl',Xm_bl);
run.meta.Xm_hybrid= struct('tr',Xm_hyb_tr,'te',Xm_hyb_te,'bl',Xm_hyb_bl);
run.meta.y_tr      = T_tr.VS;
run.meta.y_te      = T_te.VS;
run.meta.feat_tr   = X_tr_raw;
run.meta.feat_te   = X_te_raw;

% Assertions: column consistency
assert(size(Xm_te,2)==size(Xm_tr,2),'Ridge meta cols mismatch tr/te');
assert(size(Xm_bl,2)==size(Xm_tr,2),'Ridge meta cols mismatch tr/bl');
assert(size(Xm_hyb_te,2)==size(Xm_hyb_tr,2),'Hybrid meta cols mismatch');

fprintf('  [META] Ridge meta: %d cols | Hybrid meta: %d cols\n', ...
    size(Xm_tr,2), size(Xm_hyb_tr,2));
end
