function run = tune_hyperparameters(run, cfg)
% CORE.TUNE_HYPERPARAMETERS  Hyperparameter optimization (Gate 6).
%   Well-A development only, fixed depth folds, fold-local preprocessing.
%   Objective: minimum mean blocked-CV RMSE.
%   Method: bounded grid search (Bayesian not yet available in base MATLAB).
%   Well-A internal holdout (test block) is NOT used for tuning.

out_dir = fullfile(run.folder,'04_model_development');
feat    = run.fs.S1_features;
T_A     = run.T_A_proc;
tr_mask = logical(T_A.SPLIT_FLAG);  % training block only
T_tr    = T_A(tr_mask,:);
y_tr    = T_tr.VS;
k       = cfg.split.kfold;
fold_ids= run.fold_ids;
seed    = cfg.seeds.canonical;

fprintf('  [HP] Hyperparameter search (Well-A development, CV only)...\n');
fprintf('  [HP] n_train=%d, k=%d folds\n', height(T_tr), k);

hp_history = {};

%% PNN: search over spread values
spreads = [0.1, 0.2, 0.5, 1.0, 2.0];
best_pnn = struct('spread', spreads(1), 'cv_rmse', Inf);
fprintf('  [HP] PNN spread search: %s\n', num2str(spreads));
for si = 1:numel(spreads)
    sp = spreads(si);
    hp_b = struct('spread', sp);
    rmse_folds = cv_score('pnn', T_tr, y_tr, feat, fold_ids, k, hp_b, seed, cfg);
    cv_rmse = mean(rmse_folds,'omitnan');
    hp_history{end+1} = {'pnn', sp, NaN, NaN, NaN, NaN, NaN, NaN, cv_rmse, std(rmse_folds,'omitnan')};
    if cv_rmse < best_pnn.cv_rmse
        best_pnn.spread = sp; best_pnn.cv_rmse = cv_rmse;
    end
    fprintf('    pnn spread=%.2f  cv_rmse=%.4f\n', sp, cv_rmse);
end
fprintf('  [HP] PNN best: spread=%.2f  cv_rmse=%.4f\n', best_pnn.spread, best_pnn.cv_rmse);

%% MLFFNN: search hidden size and learning rate
mlffnn_grid = {[64,32],1e-3; [32,16],1e-3; [64,32],5e-4; [128,64],1e-3};
best_mlffnn = struct('hidden',[64,32],'lr',1e-3,'cv_rmse',Inf);
fprintf('  [HP] MLFFNN search (%d configs)...\n', size(mlffnn_grid,1));
for gi = 1:size(mlffnn_grid,1)
    hd=mlffnn_grid{gi,1}; lr=mlffnn_grid{gi,2};
    hp_b=struct('hidden',hd,'lr',lr,'epochs',200,'batch',32);
    rmse_folds=cv_score('mlffnn',T_tr,y_tr,feat,fold_ids,k,hp_b,seed,cfg);
    cv_rmse=mean(rmse_folds,'omitnan');
    hp_history{end+1}={'mlffnn',NaN,lr,hd(1),hd(end),NaN,NaN,NaN,cv_rmse,std(rmse_folds,'omitnan')};
    if cv_rmse < best_mlffnn.cv_rmse
        best_mlffnn.hidden=hd; best_mlffnn.lr=lr; best_mlffnn.cv_rmse=cv_rmse;
    end
    fprintf('    mlffnn hidden=[%s] lr=%.0e  cv_rmse=%.4f\n',num2str(hd),lr,cv_rmse);
end

%% DFFNN: search hidden sizes
dffnn_grid = {[128,64,32],1e-3; [64,32,16],1e-3; [128,64],1e-3};
best_dffnn = struct('hidden',[128,64,32],'lr',1e-3,'cv_rmse',Inf);
fprintf('  [HP] DFFNN search...\n');
for gi = 1:size(dffnn_grid,1)
    hd=dffnn_grid{gi,1}; lr=dffnn_grid{gi,2};
    hp_b=struct('hidden',hd,'lr',lr,'epochs',200,'batch',32);
    rmse_folds=cv_score('dffnn',T_tr,y_tr,feat,fold_ids,k,hp_b,seed,cfg);
    cv_rmse=mean(rmse_folds,'omitnan');
    hp_history{end+1}={'dffnn',NaN,lr,hd(1),hd(end),NaN,NaN,NaN,cv_rmse,std(rmse_folds,'omitnan')};
    if cv_rmse < best_dffnn.cv_rmse
        best_dffnn.hidden=hd; best_dffnn.lr=lr; best_dffnn.cv_rmse=cv_rmse;
    end
    fprintf('    dffnn hidden=[%s] lr=%.0e  cv_rmse=%.4f\n',num2str(hd),lr,cv_rmse);
end

%% CNN1D: search kernel and filter
cnn_grid = {[3,1],32; [3,1],64; [5,1],32};
best_cnn1d = struct('kernels',[3,1],'filters',32,'lr',1e-3,'cv_rmse',Inf);
fprintf('  [HP] CNN1D search...\n');
for gi = 1:size(cnn_grid,1)
    kz=cnn_grid{gi,1}; nf=cnn_grid{gi,2};
    hp_b=struct('kernels',kz,'filters',nf,'lr',1e-3,'epochs',200,'batch',32);
    rmse_folds=cv_score('cnn1d',T_tr,y_tr,feat,fold_ids,k,hp_b,seed,cfg);
    cv_rmse=mean(rmse_folds,'omitnan');
    hp_history{end+1}={'cnn1d',NaN,1e-3,NaN,NaN,nf,kz(1),NaN,cv_rmse,std(rmse_folds,'omitnan')};
    if cv_rmse < best_cnn1d.cv_rmse
        best_cnn1d.kernels=kz; best_cnn1d.filters=nf; best_cnn1d.cv_rmse=cv_rmse;
    end
    fprintf('    cnn1d kernels=[%s] filters=%d  cv_rmse=%.4f\n',num2str(kz),nf,cv_rmse);
end

%% Assemble frozen hyperparameters
hp = struct();
hp.pnn.spread       = best_pnn.spread;
hp.mlffnn.hidden    = best_mlffnn.hidden;
hp.mlffnn.lr        = best_mlffnn.lr;
hp.mlffnn.epochs    = 200; hp.mlffnn.batch = 32;
hp.dffnn.hidden     = best_dffnn.hidden;
hp.dffnn.lr         = best_dffnn.lr;
hp.dffnn.epochs     = 200; hp.dffnn.batch = 32;
hp.cnn1d.kernels    = best_cnn1d.kernels;
hp.cnn1d.filters    = best_cnn1d.filters;
hp.cnn1d.lr         = best_cnn1d.lr;
hp.cnn1d.epochs     = 200; hp.cnn1d.batch = 32;
hp.ridge.lambda_grid = logspace(-2,2,25);
hp.icnn.kernels     = [3,5,7]; hp.icnn.filters=32; hp.icnn.lr=1e-4; hp.icnn.epochs=200;
hp.hybrid.kernels   = [3,5,7]; hp.hybrid.filters=32; hp.hybrid.lr=1e-4; hp.hybrid.epochs=200;
hp.source           = 'CV_GRID_SEARCH';
hp.tuning_data      = sprintf('Well-A development block (n=%d, k=%d folds, fold-local preproc)', height(T_tr), k);
hp.tuning_method    = 'BLOCKED_CV_RMSE_GRID';
hp.objective        = 'min_mean_cv_rmse';

%% Save outputs
save(fullfile(out_dir,'HYPERPARAMETER_SELECTED.mat'),'hp','-v7.3');

% HYPERPARAMETER_SEARCH_HISTORY.csv
T_hist = cell2table(vertcat(hp_history{:}), 'VariableNames',...
    {'MODEL','SPREAD','LR','HIDDEN_FIRST','HIDDEN_LAST','FILTERS','KERNEL','LAMBDA','CV_RMSE','CV_RMSE_STD'});
writetable(T_hist, fullfile(out_dir,'HYPERPARAMETER_SEARCH_HISTORY.csv'));

% HYPERPARAMETER_SELECTED.csv
T_sel = table({'pnn';'mlffnn';'dffnn';'cnn1d';'ridge';'icnn';'hybrid_icnn'},...
    {best_pnn.cv_rmse;best_mlffnn.cv_rmse;best_dffnn.cv_rmse;best_cnn1d.cv_rmse;NaN;NaN;NaN},...
    'VariableNames',{'MODEL','BEST_CV_RMSE'});
writetable(T_sel, fullfile(out_dir,'HYPERPARAMETER_SELECTED.csv'));

run.hyperparams = hp;
run.gate.GATE_6_HYPERPARAMETER_TUNING = 'PASS';
fprintf('  [HP] GATE_6 = PASS (blocked-CV grid search complete)\n');
fprintf('  [HP] PNN=%.2f  MLFFNN=[%s]  DFFNN=[%s]  CNN1D filters=%d\n',...
    hp.pnn.spread, num2str(hp.mlffnn.hidden), num2str(hp.dffnn.hidden), hp.cnn1d.filters);
end

function rmse_folds = cv_score(model_name, T_tr, y_tr, feat, fold_ids, k, hp, seed, cfg)
rmse_folds = nan(k,1);
for fi = 1:k
    val_m = (fold_ids==fi); tr_m = ~val_m;
    T_inner=T_tr(tr_m,:); T_valid=T_tr(val_m,:);
    % Fold-local preprocessing (Rule §7.1)
    pm=fit_fold_pm(T_inner,feat);
    X_in =scale_pm(T_inner,feat,pm); X_va=scale_pm(T_valid,feat,pm);
    y_in =y_tr(tr_m); y_va=y_tr(val_m);
    X_in(isnan(X_in))=0; X_va(isnan(X_va))=0;
    off=cfg.seeds.(['offset_' model_name]);
    m_seed=seed+off+fi*cfg.seeds.offset_fold_mult;
    try
        mdl=models.fit_base(X_in,y_in,model_name,hp,m_seed,cfg);
        yp=core.predict_base_model(mdl,X_va);
        ok=~isnan(y_va)&~isnan(yp);
        if sum(ok)>1; rmse_folds(fi)=sqrt(mean((y_va(ok)-yp(ok)).^2)); end
    catch; rmse_folds(fi)=Inf; end
end
end

function pm=fit_fold_pm(T,feat)
pm.scaler=struct(); pm.imputation=struct();
for fi=1:numel(feat); f=feat{fi};
    if ~ismember(f,T.Properties.VariableNames); continue; end
    v=T.(f); ok=~isnan(v);
    if any(ok); pm.scaler.(f).mu=mean(v(ok)); pm.scaler.(f).sg=std(v(ok));
    if pm.scaler.(f).sg<1e-6; pm.scaler.(f).sg=1; end
    pm.imputation.(f).median=median(v(ok)); end
end; end

function X=scale_pm(T,feat,pm)
X=zeros(height(T),numel(feat));
for fi=1:numel(feat); f=feat{fi};
    if ~ismember(f,T.Properties.VariableNames)||~isfield(pm.scaler,f); continue; end
    v=T.(f); miss=isnan(v);
    if any(miss); v(miss)=pm.imputation.(f).median; end
    X(:,fi)=(v-pm.scaler.(f).mu)/pm.scaler.(f).sg;
end; end
