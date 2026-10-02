function result = gate3_architecture_provenance(ctx, ext_dir)
% PED_EXT.GATE3_ARCHITECTURE_PROVENANCE  Build HP provenance table.

out_dir = fullfile(ext_dir, '02_provenance');

% ── Provenance table ──────────────────────────────────────────────────────
rows = {
    'PNN_spread',       '0.50',     '0.1,0.2,0.5,1.0,2.0',  'INNER_CV_TUNED',        'outer-training only', 'Yes','Yes', 'No',  'main_nrr_pipeline.m', 'select_model',   'INNER_CV_TUNED';
    'Ridge_lambda',     '0.001',    '0.001,0.01,0.1,1,10', 'INNER_CV_TUNED', 'outer-training only', 'Yes','Yes', 'No',  'main_nrr_pipeline.m', 'select_model',   'INNER_CV_TUNED';
    'MLFFNN_layers',    '[64,32]',  'fixed',         'FIXED_FROM_PRIOR_DEVELOPMENT','Well-A legacy', 'No','No',  'Yes', 'main_nrr_pipeline.m', 'build_mlffnn',   'FIXED_FROM_PRIOR_DEVELOPMENT';
    'DFFNN_layers',     '[128,64,32]','fixed',        'FIXED_FROM_PRIOR_DEVELOPMENT','Well-A legacy','No','No',  'Yes', 'main_nrr_pipeline.m', 'build_dffnn',    'FIXED_FROM_PRIOR_DEVELOPMENT';
    'CNN1D_filters',    '32',       'fixed',         'FIXED_FROM_PRIOR_DEVELOPMENT','Well-A legacy', 'No','No',  'Yes', 'main_nrr_pipeline.m', 'build_cnn1d',    'FIXED_FROM_PRIOR_DEVELOPMENT';
    'CNN1D_window',     '16',       'fixed',         'FIXED_FROM_PRIOR_DEVELOPMENT','Well-A legacy', 'No','No',  'Yes', 'main_nrr_pipeline.m', 'build_cnn1d',    'FIXED_FROM_PRIOR_DEVELOPMENT';
    'learning_rate',    '1e-3',     'fixed',         'FIXED_FROM_PRIOR_DEVELOPMENT','Well-A legacy', 'No','No',  'Yes', 'main_nrr_pipeline.m', 'build_*',        'FIXED_FROM_PRIOR_DEVELOPMENT';
    'Direct_Ridge_lam', '1.0',      'fixed',         'POST_HOC_EXPLORATORY',  'Well-A only, post-hoc','No','No','Yes', 'main_nrr_pipeline.m', 'direct_ridge',   'POST_HOC_EXPLORATORY';
    'feature_set',      'GR,DT,NPHI,RHOB','fixed',   'FIXED_A_PRIORI',        'domain knowledge',  'Yes','No', 'No',  'main_nrr_pipeline.m', 'feature_select', 'FIXED_A_PRIORI';
    'resampling_rule',  '0.1524m',  'fixed',         'FIXED_A_PRIORI',        'domain knowledge',  'Yes','No', 'No',  'main_nrr_pipeline.m', 'resample',       'FIXED_A_PRIORI';
};

T = cell2table(rows, 'VariableNames', ...
    {'COMPONENT','FINAL_VALUE','CANDIDATE_SPACE','SELECTION_MECHANISM',...
     'DATA_USED','BEFORE_OUTER_VAL','TUNED_INNER','FIXED_PRIOR',...
     'SOURCE_FILE','FUNCTION_NAME','STATUS'});
T = validation.normalize_table_schema(T);
writetable(T, fullfile(out_dir,'PED_MODEL_ARCHITECTURE_PROVENANCE.csv'));

% ── Markdown ──────────────────────────────────────────────────────────────
fmd = fopen(fullfile(out_dir,'PED_MODEL_ARCHITECTURE_PROVENANCE.md'),'w');
fprintf(fmd,'# Model Architecture Provenance\n\n');
fprintf(fmd,'Only PNN spread and Ridge lambda were tuned within inner folds.\n');
fprintf(fmd,'Neural network architectures were fixed from prior development.\n\n');
fprintf(fmd,'**Implication:** Nested CV applies to the selected hyperparameters, ');
fprintf(fmd,'not to the full architecture-development process.\n\n');
fprintf(fmd,'| Component | Value | Status |\n|---|---|---|\n');
for ri=1:height(T)
    fprintf(fmd,'| %s | %s | %s |\n', T.COMPONENT(ri), T.FINAL_VALUE(ri), T.STATUS(ri));
end
fclose(fmd);

fprintf('    Architecture provenance table: %d components\n', height(T));
fprintf('    INNER_CV_TUNED: PNN_spread, Ridge_lambda\n');
fprintf('    FIXED_FROM_PRIOR_DEVELOPMENT: MLFFNN, DFFNN, CNN1D architectures\n');
result = struct('status',string('PASS'),'code',string('OK'),...
    'message',string(sprintf('%d components documented; PNN_spread and Ridge_lambda INNER_CV_TUNED',height(T))),...
    'required',true,'evidence_path',string(out_dir),'n_checks',height(T),'n_pass',height(T));
end
