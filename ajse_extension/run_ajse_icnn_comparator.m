function result = run_ajse_icnn_comparator(project_root, varargin)
% RUN_AJSE_ICNN_COMPARATOR  Leakage-controlled I-CNN comparator extension.
%
% This runner does not alter the corrected canonical run. It rebuilds the
% fold-local base meta-features required for fair I-CNN and Hybrid I-CNN
% comparisons, then evaluates the models at three levels:
%   1) true outer depth-blocked CV on Well-A development rows;
%   2) contiguous same-well holdout;
%   3) full-Well-A deployment to external Well-B Pop-A/Pop-B.
%
% The historical I-CNN architecture is frozen; Well-B is never used for
% fitting or hyperparameter selection. Results are post-hoc comparators.

if nargin<1 || isempty(project_root)
    project_root=fileparts(fileparts(mfilename('fullpath')));
end
reference_run_id='run_PED_corrected_20260910_071523';
seed=42; epochs=200;
for k=1:2:numel(varargin)
    switch lower(string(varargin{k}))
        case "reference_run_id"; reference_run_id=char(varargin{k+1});
        case "seed"; seed=double(varargin{k+1});
        case "epochs"; epochs=double(varargin{k+1});
        otherwise; error('run_ajse_icnn_comparator:UnknownOption', ...
                'Unknown option %s',string(varargin{k}));
    end
end

addpath(project_root);
addpath(fullfile(project_root,'config'));
extension_dir=fullfile(project_root,'ajse_extension');
if ~isfolder(extension_dir)
    % Backward-compatible local folder name used by the original run.
    extension_dir=fullfile(project_root,'AJSE_ICNN_Extension');
end
assert(isfolder(extension_dir),'AJSE comparator extension folder not found');
addpath(genpath(extension_dir));
cfg=config_nrr_v5();
assert(seed==cfg.seeds.canonical, ...
    'Canonical comparator run must use seed %d',cfg.seeds.canonical);
assert(epochs==200, ...
    'Publication run must retain the frozen historical 200 epochs');
assert(license('test','Neural_Network_Toolbox')==1, ...
    'Deep Learning Toolbox is required');

reference_dir=fullfile(project_root,'runs',reference_run_id);
frozen_path=fullfile(reference_dir,'08_freeze','FROZEN_NUMERICAL_RUN.mat');
manifest_path=fullfile(reference_dir,'08_freeze','RUN_MANIFEST_SHA256.csv');
assert(isfile(frozen_path)&&isfile(manifest_path), ...
    'Corrected frozen reference or manifest is missing');
S=load(frozen_path,'run'); ref=S.run;
assert(strcmp(ref.id,reference_run_id), 'Reference run ID mismatch');
assert(strcmp(ref.gate.GATE_17,'PASS'), 'Reference Gate 17 is not PASS');
assert(ref.n_dev==392 && ref.n_hold==100 && ref.n_popA==329 && ref.n_popB==236, ...
    'Reference population counts do not match the corrected analysis');

run_id=sprintf('run_AJSE_ICNN_corrected_%s', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss')));
out_dir=fullfile(project_root,'runs',run_id);
for d={'00_provenance','01_nested_cv','02_holdout','03_external','04_freeze'}
    mkdir(fullfile(out_dir,d{1}));
end
log_path=fullfile(out_dir,'AJSE_ICNN_RUN_LOG.txt');
diary(log_path); cleanup_diary=onCleanup(@()diary('off'));

fprintf('\n%s\nAJSE I-CNN COMPARATOR EXTENSION\n%s\n', ...
    repmat('=',1,72),repmat('=',1,72));
fprintf('Run ID: %s\nReference: %s\nSeed: %d\n',run_id,reference_run_id,seed);
fprintf('Status: HISTORICAL_ARCHITECTURE_POST_HOC_REEVALUATION\n');

meta_hp=ajse_icnn.fixed_hp(epochs);
config=struct('run_id',run_id,'reference_run_id',reference_run_id, ...
    'seed',seed,'created_at',datestr(now,30),'provenance_class', ...
    'HISTORICAL_ARCHITECTURE_POST_HOC_REEVALUATION', ...
    'wellB_used_for_tuning',false,'meta_hp',meta_hp, ...
    'matlab_version',version,'execution_environment','cpu');
fid=fopen(fullfile(out_dir,'00_provenance','AJSE_ICNN_CONFIG.json'),'w');
assert(fid>=3,'Cannot create configuration JSON');
fprintf(fid,'%s',jsonencode(config,'PrettyPrint',true)); fclose(fid);

t_all=tic;
fprintf('\n[LEVEL 1] True outer depth-blocked CV\n');
nested=run_nested_level(ref,cfg,meta_hp,seed,out_dir);
fprintf('\n[LEVEL 2] Corrected contiguous holdout and dev-frozen transfer\n');
holdout=run_holdout_level(ref,cfg,meta_hp,seed,out_dir);
fprintf('\n[LEVEL 3] Full-Well-A external deployment comparison\n');
external=run_external_level(ref,cfg,meta_hp,seed,out_dir);

result=struct();
result.id=run_id; result.folder=out_dir; result.seed=seed;
result.reference_run_id=reference_run_id;
result.provenance='HISTORICAL_ARCHITECTURE_POST_HOC_REEVALUATION';
result.status='PASS'; result.meta_hp=meta_hp;
result.nested=nested.numerical;
result.holdout=holdout.numerical;
result.external=external.numerical;
result.elapsed_seconds=toc(t_all);
result.invariants=struct('wellB_used_for_tuning',false, ...
    'segment_aware_windows',true,'cross_segment_windows_retained',0, ...
    'reference_run_unchanged',true,'canonical_seed',seed);

write_summary(result,out_dir);
save(fullfile(out_dir,'04_freeze','AJSE_ICNN_NUMERICAL_RUN.mat'), ...
    'result','-v7.3');
models=struct('holdout_icnn',holdout.icnn, ...
    'holdout_hybrid_icnn',holdout.hybrid, ...
    'external_icnn',external.icnn, ...
    'external_hybrid_icnn',external.hybrid);
save(fullfile(out_dir,'04_freeze','AJSE_ICNN_MODEL_ARTIFACTS.mat'), ...
    'models','-v7.3');

write_source_manifest(project_root,out_dir,manifest_path);
write_output_manifest(out_dir);
fprintf('\n[PASS] AJSE I-CNN comparator extension completed in %.1f min\n', ...
    result.elapsed_seconds/60);
fprintf('Output: %s\n',out_dir);
clear cleanup_diary; diary('off');
end

function out=run_nested_level(ref,cfg,meta_hp,seed,out_dir)
T_dev=ref.T_A_raw(ref.roles.dev_mask,:);
k=cfg.cv.n_outer; n=height(T_dev);
pred=nan(n,3); measured=nan(n,1); row_id=zeros(n,1); depth=nan(n,1);
fold_rows=cell(k*3,8); fr=0; training_rows=cell(k*2,8); tr=0;

for fo=1:k
    t_fold=tic;
    fprintf('[NESTED] Fold %d/%d\n',fo,k);
    ti=ref.outer_folds(fo).train_idx; vi=ref.outer_folds(fo).val_idx;
    T_tr=T_dev(ti,:); T_val=T_dev(vi,:); hp=ref.cv.fold_hp{fo};
    inner=nrr_data.build_folds(T_tr,cfg.cv.n_inner,cfg);
    [oof_meta,~]=nrr_models.generate_inner_oof(T_tr,inner,hp,seed,fo,cfg);

    pm=nrr_data.fit_pm(T_tr,cfg);
    [Xtr,ytr]=nrr_data.apply_pm_deploy(T_tr,pm,cfg);
    [Xv,yv]=nrr_data.apply_pm(T_val,pm,cfg);
    segtr=nrr_data.depth_segment_ids(T_tr.(cfg.data.depth_col),cfg);
    segv=nrr_data.depth_segment_ids(T_val.(cfg.data.depth_col),cfg);
    [base,~]=nrr_models.fit_base_set(Xtr,ytr,hp,seed,fo,cfg,segtr);
    [meta_v,~]=nrr_models.predict_base_set(base,Xv,segv);
    scaler=nrr_models.fit_meta_scaler(oof_meta);
    oof_sc=nrr_models.apply_meta_scaler(oof_meta,scaler);
    meta_v_sc=nrr_models.apply_meta_scaler(meta_v,scaler);
    ridge=nrr_models.fit_ridge_stacker(oof_sc,ytr,hp.ridge_lambda,cfg);
    yr=nrr_models.predict_ridge_stacker(ridge,meta_v_sc);
    diff_ref=max(abs(yr-ref.cv.oof_pred(vi)));
    assert(diff_ref<=1e-4, ...
        'Nested Ridge reproduction mismatch fold %d: %.3g',fo,diff_ref);

    mi=ajse_icnn.fit_model(oof_sc,ytr,meta_hp, ...
        seed+601+fo*cfg.seeds.offset_fold,segtr,'icnn');
    mh=ajse_icnn.fit_model([Xtr oof_sc],ytr,meta_hp, ...
        seed+701+fo*cfg.seeds.offset_fold,segtr,'hybrid_icnn');
    yi=ajse_icnn.predict_model(mi,meta_v_sc,segv);
    yh=ajse_icnn.predict_model(mh,[Xv meta_v_sc],segv);

    pred(vi,:)=[yr yi yh]; measured(vi)=yv;
    row_id(vi)=T_val.(cfg.data.id_col); depth(vi)=T_val.(cfg.data.depth_col);
    names=["Ridge_stacker" "I_CNN" "Hybrid_I_CNN"];
    for mj=1:3
        mm=nrr_eval.metrics(yv,pred(vi,mj)); fr=fr+1;
        fold_rows(fr,:)={fo,names(mj),mm.n,mm.r2,mm.rmse,mm.mae,mm.bias,diff_ref};
    end
    tr=tr+1; training_rows(tr,:)={fo,"I_CNN",mi.seed,mi.n_train_rows, ...
        mi.n_segments,mi.n_valid_windows,mi.n_discarded_cross_segment,mi.elapsed_seconds};
    tr=tr+1; training_rows(tr,:)={fo,"Hybrid_I_CNN",mh.seed,mh.n_train_rows, ...
        mh.n_segments,mh.n_valid_windows,mh.n_discarded_cross_segment,mh.elapsed_seconds};
    fprintf('[NESTED] Fold %d PASS | Ridge %.4f | I-CNN %.4f | Hybrid %.4f | %.1f min\n', ...
        fo,nrr_eval.r2(yv,yr),nrr_eval.r2(yv,yi),nrr_eval.r2(yv,yh),toc(t_fold)/60);
    checkpoint=struct('completed_fold',fo,'pred',pred,'measured',measured, ...
        'row_id',row_id,'depth',depth); %#ok<NASGU>
    save(fullfile(out_dir,'01_nested_cv','NESTED_CHECKPOINT.mat'),'checkpoint','-v7.3');
end
assert(all(isfinite(pred),'all')&&all(isfinite(measured))&&all(row_id>0));
names=["Ridge_stacker";"I_CNN";"Hybrid_I_CNN"];
metrics_table=metrics_table_for(measured,pred,names,"NESTED_OUTER_OOF");
fold_table=cell2table(fold_rows,'VariableNames', ...
    {'FOLD','MODEL','N','R2','RMSE','MAE','BIAS','RIDGE_REPRO_MAX_DIFF'});
training_table=cell2table(training_rows,'VariableNames', ...
    {'FOLD','MODEL','SEED','N_TRAIN','N_SEGMENTS','N_VALID_WINDOWS', ...
    'N_DISCARDED_CROSS_SEGMENT','FIT_SECONDS'});
writetable(table(row_id,depth,measured,pred(:,1),pred(:,2),pred(:,3), ...
    'VariableNames',{'ROW_ID','DEPTH','VS_MEASURED','PRED_RIDGE_STACKER', ...
    'PRED_I_CNN','PRED_HYBRID_I_CNN'}), ...
    fullfile(out_dir,'01_nested_cv','AJSE_NESTED_OOF_PREDICTIONS.csv'));
writetable(metrics_table,fullfile(out_dir,'01_nested_cv','AJSE_NESTED_POOLED_METRICS.csv'));
writetable(fold_table,fullfile(out_dir,'01_nested_cv','AJSE_NESTED_FOLD_METRICS.csv'));
writetable(training_table,fullfile(out_dir,'01_nested_cv','AJSE_NESTED_TRAINING_LEDGER.csv'));
out.numerical=struct('predictions',pred,'measured',measured, ...
    'metrics',metrics_table,'fold_metrics',fold_table,'training_ledger',training_table);
end

function out=run_holdout_level(ref,cfg,meta_hp,seed,out_dir)
T_dev=ref.T_A_raw(ref.roles.dev_mask,:); T_hold=ref.T_A_raw(ref.roles.hold_mask,:);
hp=ref.canon_hp; inner=nrr_data.build_folds(T_dev,cfg.cv.n_inner,cfg);
[oof_meta,~]=nrr_models.generate_inner_oof(T_dev,inner,hp,seed,0,cfg);
pm=nrr_data.fit_pm(T_dev,cfg);
[Xd,yd]=nrr_data.apply_pm_deploy(T_dev,pm,cfg);
[Xh,yh]=nrr_data.apply_pm(T_hold,pm,cfg);
segd=nrr_data.depth_segment_ids(T_dev.(cfg.data.depth_col),cfg);
segh=nrr_data.depth_segment_ids(T_hold.(cfg.data.depth_col),cfg);
[base,~]=nrr_models.fit_base_set(Xd,yd,hp,seed,0,cfg,segd);
[meta_h,~]=nrr_models.predict_base_set(base,Xh,segh);
scaler=nrr_models.fit_meta_scaler(oof_meta);
oof_sc=nrr_models.apply_meta_scaler(oof_meta,scaler);
meta_h_sc=nrr_models.apply_meta_scaler(meta_h,scaler);
ridge=nrr_models.fit_ridge_stacker(oof_sc,yd,hp.ridge_lambda,cfg);
yr=nrr_models.predict_ridge_stacker(ridge,meta_h_sc);
assert(max(abs(yr-ref.hist.predictions(:,5)))<=1e-4, ...
    'Holdout corrected Ridge reproduction mismatch');

mi=ajse_icnn.fit_model(oof_sc,yd,meta_hp,seed+601,segd,'icnn');
mh=ajse_icnn.fit_model([Xd oof_sc],yd,meta_hp,seed+701,segd,'hybrid_icnn');
yi=ajse_icnn.predict_model(mi,meta_h_sc,segh);
yhy=ajse_icnn.predict_model(mh,[Xh meta_h_sc],segh);
P=[yr yi yhy]; names=["Ridge_stacker";"I_CNN";"Hybrid_I_CNN"];
metrics=metrics_table_for(yh,P,names,"CONTIGUOUS_HOLDOUT");
writetable(table(T_hold.(cfg.data.id_col),T_hold.(cfg.data.depth_col),yh, ...
    P(:,1),P(:,2),P(:,3),'VariableNames',{'ROW_ID','DEPTH','VS_MEASURED', ...
    'PRED_RIDGE_STACKER','PRED_I_CNN','PRED_HYBRID_I_CNN'}), ...
    fullfile(out_dir,'02_holdout','AJSE_HOLDOUT_PREDICTIONS.csv'));
writetable(metrics,fullfile(out_dir,'02_holdout','AJSE_HOLDOUT_METRICS.csv'));

% Development-frozen transfer is diagnostic and is not substituted for the
% full-Well-A external deployment comparison below.
T_B=ref.T_B_raw; [Xb,yb]=nrr_data.apply_pm_deploy(T_B,pm,cfg);
segb=nrr_data.depth_segment_ids(T_B.(cfg.data.depth_col),cfg);
[meta_b,~]=nrr_models.predict_base_set(base,Xb,segb);
meta_b_sc=nrr_models.apply_meta_scaler(meta_b,scaler);
Pdev=[nrr_models.predict_ridge_stacker(ridge,meta_b_sc), ...
    ajse_icnn.predict_model(mi,meta_b_sc,segb), ...
    ajse_icnn.predict_model(mh,[Xb meta_b_sc],segb)];
dev_rows=population_metrics(yb,Pdev,names,ref.roles.popA_mask, ...
    ref.roles.popB_mask,"DEVELOPMENT_FROZEN_DIAGNOSTIC");
writetable(dev_rows,fullfile(out_dir,'02_holdout','AJSE_DEV_FROZEN_EXTERNAL_METRICS.csv'));
out.icnn=mi; out.hybrid=mh;
out.numerical=struct('predictions',P,'measured',yh,'metrics',metrics, ...
    'dev_frozen_external_metrics',dev_rows);
end

function out=run_external_level(ref,cfg,meta_hp,seed,out_dir)
T=ref.T_A_raw; T_B=ref.T_B_raw; hp=ref.canon_hp;
folds=nrr_data.build_folds(T,cfg.cv.n_outer,cfg);
n=height(T); oof=nan(n,4);
for fo=1:cfg.cv.n_outer
    fprintf('[EXTERNAL OOF] Fold %d/%d\n',fo,cfg.cv.n_outer);
    ti=folds(fo).train_idx; vi=folds(fo).val_idx;
    pm=nrr_data.fit_pm(T(ti,:),cfg);
    [Xt,yt]=nrr_data.apply_pm_deploy(T(ti,:),pm,cfg);
    [Xv,~]=nrr_data.apply_pm(T(vi,:),pm,cfg);
    segt=nrr_data.depth_segment_ids(T(ti,:).(cfg.data.depth_col),cfg);
    segv=nrr_data.depth_segment_ids(T(vi,:).(cfg.data.depth_col),cfg);
    base_seed=seed+fo*cfg.seeds.offset_fold+100000;
    [base,~]=nrr_models.fit_base_set(Xt,yt,hp,base_seed,fo,cfg,segt);
    [oof(vi,:),~]=nrr_models.predict_base_set(base,Xv,segv);
end
assert(all(isfinite(oof),'all'),'Full-Well-A OOF matrix is incomplete');

[Xfull,yfull]=nrr_data.apply_pm_deploy(T,ref.deploy.pm,cfg);
[Xb,yb]=nrr_data.apply_pm_deploy(T_B,ref.deploy.pm,cfg);
segfull=nrr_data.depth_segment_ids(T.(cfg.data.depth_col),cfg);
segb=nrr_data.depth_segment_ids(T_B.(cfg.data.depth_col),cfg);
[meta_b,~]=nrr_models.predict_base_set(ref.deploy.base_nets,Xb,segb);
scaler=nrr_models.fit_meta_scaler(oof);
oof_sc=nrr_models.apply_meta_scaler(oof,scaler);
meta_b_sc=nrr_models.apply_meta_scaler(meta_b,scaler);
ridge=nrr_models.fit_ridge_stacker(oof_sc,yfull,hp.ridge_lambda,cfg);
yr=nrr_models.predict_ridge_stacker(ridge,meta_b_sc);
assert(max(abs(yr-ref.blind.y_raw))<=1e-4, ...
    'Full deployment corrected Ridge reproduction mismatch');

mi=ajse_icnn.fit_model(oof_sc,yfull,meta_hp,seed+90601,segfull,'icnn');
mh=ajse_icnn.fit_model([Xfull oof_sc],yfull,meta_hp,seed+90701,segfull,'hybrid_icnn');
yi=ajse_icnn.predict_model(mi,meta_b_sc,segb);
yhy=ajse_icnn.predict_model(mh,[Xb meta_b_sc],segb);
P=[yr yi yhy ref.posthoc.y_pred];
names=["Ridge_stacker";"I_CNN";"Hybrid_I_CNN";"Direct_Ridge"];
metrics=population_metrics(yb,P,names,ref.roles.popA_mask, ...
    ref.roles.popB_mask,"FULL_WELLA_EXTERNAL_DEPLOYMENT");
writetable(metrics,fullfile(out_dir,'03_external','AJSE_EXTERNAL_POPULATION_METRICS.csv'));
writetable(table(T_B.(cfg.data.id_col),T_B.(cfg.data.depth_col),yb, ...
    ref.roles.popA_mask,ref.roles.popB_mask,P(:,1),P(:,2),P(:,3),P(:,4), ...
    'VariableNames',{'ROW_ID','DEPTH','VS_MEASURED','IS_POPA','IS_POPB', ...
    'PRED_RIDGE_STACKER','PRED_I_CNN','PRED_HYBRID_I_CNN','PRED_DIRECT_RIDGE'}), ...
    fullfile(out_dir,'03_external','AJSE_EXTERNAL_ROW_PREDICTIONS.csv'));

mask=ref.roles.popA_mask;
boot=ajse_icnn.paired_block_bootstrap(yb(mask),P(mask,:),names, ...
    cfg.boot.primary_bl,cfg.boot.n_rep,cfg.seeds.bootstrap);
boot.PROVENANCE=repmat("POST_HOC_PAIRED_BLOCK_BOOTSTRAP",height(boot),1);
writetable(boot,fullfile(out_dir,'03_external','AJSE_POPA_PAIRED_BLOCK_BOOTSTRAP.csv'));
out.icnn=mi; out.hybrid=mh;
out.numerical=struct('predictions',P,'measured',yb,'metrics',metrics, ...
    'bootstrap',boot);
end

function T=metrics_table_for(y,P,names,level)
rows=cell(numel(names),9);
for i=1:numel(names)
    m=nrr_eval.metrics(y,P(:,i));
    rows(i,:)={string(level),names(i),status_for(names(i)),m.n,m.r2, ...
        m.rmse,m.mae,m.bias,"RAW_UNCLIPPED"};
end
T=cell2table(rows,'VariableNames',{'LEVEL','MODEL','STATUS','N','R2', ...
    'RMSE','MAE','BIAS','PREDICTION_POLICY'});
end

function T=population_metrics(y,P,names,popA,popB,level)
rows=cell(numel(names)*2,10); ri=0;
for pi=1:2
    if pi==1; mask=logical(popA); pop="POP_A_PRIMARY_NON_DUPLICATE";
    else; mask=logical(popB); pop="POP_B_TARGET_INFORMED_DIAGNOSTIC"; end
    for mi=1:numel(names)
        m=nrr_eval.metrics(y(mask),P(mask,mi)); ri=ri+1;
        rows(ri,:)={string(level),pop,names(mi),status_for(names(mi)), ...
            m.n,m.r2,m.rmse,m.mae,m.bias,"RAW_UNCLIPPED"};
    end
end
T=cell2table(rows,'VariableNames',{'LEVEL','POPULATION','MODEL','STATUS', ...
    'N','R2','RMSE','MAE','BIAS','PREDICTION_POLICY'});
end

function s=status_for(name)
switch string(name)
    case "Ridge_stacker"; s="FROZEN_PRIMARY_REFERENCE";
    case "Direct_Ridge"; s="POST_HOC_SENSITIVITY";
    otherwise; s="HISTORICAL_ARCHITECTURE_POST_HOC_REEVALUATION";
end
end

function write_summary(result,out_dir)
path=fullfile(out_dir,'04_freeze','AJSE_ICNN_RESULTS_SUMMARY.md');
fid=fopen(path,'w'); assert(fid>=3,'Cannot create summary');
c=onCleanup(@()fclose(fid));
fprintf(fid,'# AJSE I-CNN comparator results\n\n');
fprintf(fid,'- Run: `%s`\n',result.id);
fprintf(fid,'- Corrected reference: `%s`\n',result.reference_run_id);
fprintf(fid,'- Provenance: `%s`\n',result.provenance);
fprintf(fid,'- Well-B used for fitting/tuning: **No**\n');
fprintf(fid,'- Cross-segment windows retained: **0**\n\n');
fprintf(fid,'## Interpretation rule\n\n');
fprintf(fid,['I-CNN and Hybrid I-CNN are additional post-hoc comparators. ' ...
    'They do not replace the frozen primary Ridge stacker and must not be ' ...
    'described as prospectively pre-specified.\n\n']);
fprintf(fid,'## Nested outer OOF\n\n');
write_metric_lines(fid,result.nested.metrics);
fprintf(fid,'\n## Contiguous holdout\n\n');
write_metric_lines(fid,result.holdout.metrics);
fprintf(fid,'\n## Full-Well-A external deployment\n\n');
T=result.external.metrics;
for p=["POP_A_PRIMARY_NON_DUPLICATE","POP_B_TARGET_INFORMED_DIAGNOSTIC"]
    fprintf(fid,'\n### %s\n\n',p);
    write_metric_lines(fid,T(T.POPULATION==p,:));
end
fprintf(fid,'\nTotal elapsed time: %.1f minutes.\n',result.elapsed_seconds/60);
clear c
end

function write_metric_lines(fid,T)
for i=1:height(T)
    fprintf(fid,'- %s: R2 %.4f; RMSE %.4f; MAE %.4f; bias %+.4f; n=%d.\n', ...
        T.MODEL(i),T.R2(i),T.RMSE(i),T.MAE(i),T.BIAS(i),T.N(i));
end
end

function write_source_manifest(project_root,out_dir,reference_manifest)
src_dir=fullfile(project_root,'AJSE_ICNN_Extension');
files=dir(fullfile(src_dir,'**','*.m'));
rows=cell(numel(files)+1,3);
for i=1:numel(files)
    p=fullfile(files(i).folder,files(i).name);
    rows(i,:)={string(strrep(p,project_root,'')), ...
        string(nrr_eval.sha256_file_windows(p)),"SOURCE"};
end
rows(end,:)={string(strrep(reference_manifest,project_root,'')), ...
    string(nrr_eval.sha256_file_windows(reference_manifest)),"REFERENCE_MANIFEST"};
writetable(cell2table(rows,'VariableNames',{'FILE','SHA256','ROLE'}), ...
    fullfile(out_dir,'00_provenance','AJSE_ICNN_SOURCE_MANIFEST.csv'));
end

function write_output_manifest(out_dir)
files=dir(fullfile(out_dir,'**','*'));
rows={};
for i=1:numel(files)
    if files(i).isdir; continue; end
    p=fullfile(files(i).folder,files(i).name);
    if strcmpi(files(i).name,'AJSE_ICNN_RUN_LOG.txt') || ...
            strcmpi(files(i).name,'AJSE_ICNN_OUTPUT_MANIFEST.csv')
        continue
    end
    rows(end+1,:)={string(strrep(p,[out_dir filesep],'')), ...
        string(nrr_eval.sha256_file_windows(p)),files(i).bytes}; %#ok<AGROW>
end
writetable(cell2table(rows,'VariableNames',{'FILE','SHA256','BYTES'}), ...
    fullfile(out_dir,'04_freeze','AJSE_ICNN_OUTPUT_MANIFEST.csv'));
end
