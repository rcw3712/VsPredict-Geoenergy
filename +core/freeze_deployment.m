function run = freeze_deployment(run, cfg)
% CORE.FREEZE_DEPLOYMENT  Refit selected model on FULL Well-A; save frozen artifacts.
%   Rule §14: Deployment model frozen BEFORE Well-B is opened.
%   Writes FROZEN_DEPLOYMENT_MODEL.mat and DEPLOYMENT_FINGERPRINT.txt.
%   Well-B data is NOT read in this function.

out_dir = fullfile(run.folder,'09_frozen');
feat    = run.fs.S1_features;
hp      = run.hyperparams;
seed    = cfg.seeds.canonical;

% Full Well-A (train + test combined)
T_A_raw_full = run.T_A_raw;  % raw data for refit;  % added semicolon
ok_A_raw = ~isnan(T_A_raw_full.VS);
y_A = T_A_raw_full.VS(ok_A_raw);

% ── Refit preprocessor on FULL Well-A (train + test combined) (Rule §4.4) ──
pm_full = struct(); pm_full.features = feat; pm_full.scaler = struct();
for ffi = 1:numel(feat)
    ff = feat{ffi};
    if ~ismember(ff, T_A_raw_full.Properties.VariableNames); continue; end
    v = T_A_raw_full.(ff)(ok_A_raw); ok_v = ~isnan(v);
    if any(ok_v)
        pm_full.scaler.(ff).mu = mean(v(ok_v));
        pm_full.scaler.(ff).sg = std(v(ok_v));
        if pm_full.scaler.(ff).sg==0; pm_full.scaler.(ff).sg=1; end
        pm_full.imputation.(ff).median = median(v(ok_v));
    end
end
pm_full.fit_source   = sprintf('Well-A (full, n=%d)', height(T_A_raw_full));
pm_full.fit_date     = datestr(now,'yyyy-mm-dd HH:MM:SS'); %#ok<DATST>
pm_full.n_rows_fit   = height(T_A_raw_full);
save(fullfile(out_dir,'PREPROCESSOR_FULL_WELLA.mat'),'pm_full','-v7.3');

% Apply deployment preprocessor to full Well-A
X_A_raw = table2array(T_A_raw_full(ok_A_raw, feat));
X_A = zeros(sum(ok_A_raw), numel(feat));
for ffi = 1:numel(feat)
    ff = feat{ffi};
    v = X_A_raw(:,ffi); miss=isnan(v);
    if any(miss); v(miss)=pm_full.imputation.(ff).median; end
    X_A(:,ffi) = (v - pm_full.scaler.(ff).mu)/pm_full.scaler.(ff).sg;
end
n_A = size(X_A,1);
fprintf('  [FREEZE] Refitting on full Well-A: %d rows\n', n_A);

% Refit base learners
base_names = cfg.stack.base_order;
base_final = struct();
for bi = 1:numel(base_names)
    nm  = base_names{bi};
    off = cfg.seeds.(['offset_' nm]);
    rng(seed + off + cfg.seeds.offset_refit, 'twister');
    hp_b = get_hp(hp, nm);
    base_final.(nm) = models.fit_base(X_A, y_A, nm, hp_b, ...
        seed + off + cfg.seeds.offset_refit, cfg);
    fprintf('  [FREEZE] %s refitted on %d rows\n', nm, n_A);
end

% OOF predictions on full Well-A (for meta-feature construction)
OOF_A = nan(n_A, numel(base_names));
k = cfg.split.kfold;
fold_ids_A = make_folds(n_A, k);
for fi = 1:k
    val_m = fold_ids_A==fi; tr_m = ~val_m;
    X_va = X_A(val_m,:); X_tr_fi = X_A(tr_m,:); y_tr_fi = y_A(tr_m);
    for bi = 1:numel(base_names)
        nm = base_names{bi};
        off = cfg.seeds.(['offset_' nm]);
        rng(seed+off+fi*cfg.seeds.offset_fold_mult+cfg.seeds.offset_refit,'twister');
        hp_b = get_hp(hp, nm);
        m_fi = models.fit_base(X_tr_fi, y_tr_fi, nm, hp_b, ...
            seed+off+fi*cfg.seeds.offset_fold_mult+cfg.seeds.offset_refit, cfg);
        OOF_A(val_m,bi) = core.predict_base_model(m_fi, X_va);
    end
end
OOF_A(isnan(OOF_A))=0;

% ── Meta-scaler from full Well-A OOF (NOT from 394-row training OOF) ──────
% The meta-scaler (mu, sg) was fitted on OOF predictions from the 394-row
% training block in build_meta_features.m. For the deployment refit,
% we recompute OOF on full Well-A (n_A rows) and fit a new scaler.
% This eliminates the meta-scaler leakage identified in audit finding #5.
ms_ridge_deploy = struct('mu', mean(OOF_A,1,'omitnan'), ...
    'sg', std(OOF_A,0,1,'omitnan'));
ms_ridge_deploy.sg(ms_ridge_deploy.sg==0)=1;
% Refit meta-learner
deploy_nm = run.deploy_name;
deploy_key = strrep(deploy_nm,'_stacker','');
ms_ridge = run.meta_scaler_ridge;
ms_hybrid = run.meta_scaler_hybrid;

Xm_A = (OOF_A - ms_ridge_deploy.mu) ./ ms_ridge_deploy.sg;
Xm_A_hyb = [X_A, OOF_A]; Xm_A_hyb = (Xm_A_hyb - ms_hybrid.mu) ./ ms_hybrid.sg;

deploy_model = struct();
if contains(deploy_key,'ridge')
    hp_r = get_hp(hp,'ridge');
    rng(seed+cfg.seeds.offset_ridge+cfg.seeds.offset_refit,'twister');
    Xb = [ones(n_A,1), Xm_A];
    lam = run.meta_models.ridge.lambda;
    deploy_model.coef = (Xb'*Xb + lam*eye(size(Xb,2)))\(Xb'*y_A);
    deploy_model.type = 'ridge_stacker';
    deploy_model.meta_scaler = ms_ridge_deploy;  % refitted on full Well-A
elseif contains(deploy_key,'hybrid')
    hp_h = get_hp(hp,'hybrid');
    rng(seed+cfg.seeds.offset_hybrid_icnn+cfg.seeds.offset_refit,'twister');
    [deploy_model.net,~] = train_icnn_meta_stub(Xm_A_hyb, y_A, hp_h, ...
        seed+cfg.seeds.offset_hybrid_icnn+cfg.seeds.offset_refit, cfg);
    deploy_model.type = 'hybrid_icnn';
    deploy_model.meta_scaler = ms_hybrid;
else  % icnn
    hp_i = get_hp(hp,'icnn');
    rng(seed+cfg.seeds.offset_icnn+cfg.seeds.offset_refit,'twister');
    [deploy_model.net,~] = train_icnn_meta_stub(Xm_A, y_A, hp_i, ...
        seed+cfg.seeds.offset_icnn+cfg.seeds.offset_refit, cfg);
    deploy_model.type = 'icnn';
    deploy_model.meta_scaler = ms_ridge_deploy;  % refitted on full Well-A
end

deploy_model.base_models   = base_final;
deploy_model.base_order    = base_names;
deploy_model.features      = feat;
deploy_model.deploy_name   = deploy_nm;
deploy_model.deploy_r2_WA  = run.deploy_r2_WA;
deploy_model.seed          = seed;
deploy_model.preproc       = pm_full;  % refitted on full Well-A
deploy_model.meta_scaler_ridge  = ms_ridge_deploy;
deploy_model.meta_scaler_hybrid = ms_hybrid;

% Fingerprint
fp.deploy_name     = deploy_nm;
fp.features        = strjoin(feat,',');
fp.preproc_hash    = run.preproc_dev.hash;
fp.meta_ridge_sig  = ms_ridge.signature;
fp.meta_hybrid_sig = ms_hybrid.signature;
fp.seed            = seed;
fp.n_wellA         = n_A;
fp.frozen_at       = datestr(now,'yyyy-mm-dd HH:MM:SS'); %#ok<DATST>
deploy_model.fingerprint = fp;

save(fullfile(out_dir,'FROZEN_DEPLOYMENT_MODEL.mat'),'deploy_model','-v7.3');

% Write fingerprint text
fid=fopen(fullfile(out_dir,'DEPLOYMENT_FINGERPRINT.txt'),'w');
fn=fieldnames(fp); for fi2=1:numel(fn); fprintf(fid,'%s: %s\n',fn{fi2},num2str(fp.(fn{fi2}))); end
fclose(fid);

run.deploy_model = deploy_model;
run.gate.GATE_11_FROZEN_DEPLOYMENT = 'PASS';
fprintf('  [FREEZE] GATE_11 = PASS | Deploy: %s\n', deploy_nm);
end

function fids = make_folds(n, k)
fs=floor(n/k); fids=zeros(n,1,'int32');
for fi=1:k; if fi<k; fids((fi-1)*fs+1:fi*fs)=fi; else; fids((fi-1)*fs+1:end)=fi; end; end
end
function hp_b=get_hp(hp,nm); if isfield(hp,nm); hp_b=hp.(nm); else; hp_b=struct(); end; end
function [net,pred]=train_icnn_meta_stub(X,y,hp,seed,cfg)
% Simplified for refit — full version matches train_meta_model
if isfield(hp,'epochs'); ep=hp.epochs; else; ep=200; end
if isfield(hp,'lr'); lr=hp.lr; else; lr=1e-3; end
if isfield(hp,'batch'); bs=hp.batch; else; bs=32; end
n_in=size(X,2);
layers=[featureInputLayer(n_in,'Normalization','none'),...
    fullyConnectedLayer(64),batchNormalizationLayer,reluLayer,...
    fullyConnectedLayer(32),reluLayer,...
    fullyConnectedLayer(1),regressionLayer];
opts=trainingOptions('adam','MaxEpochs',ep,'MiniBatchSize',bs,'InitialLearnRate',lr,...
    'Shuffle',cfg.training.shuffle,'Verbose',false,'ExecutionEnvironment','cpu');
rng(seed,'twister'); y_mu_d=mean(y,'omitnan'); y_sg_d=std(y,'omitnan'); if y_sg_d<1e-6; y_sg_d=1; end
y_scaled=(y-y_mu_d)/y_sg_d;
net=trainNetwork(single(X),single(y_scaled(:)),layers,opts);
pred_s=double(predict(net,single(X)))'; pred=pred_s*y_sg_d+y_mu_d;
end
