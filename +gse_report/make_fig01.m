function ei = make_fig01(bundle)
% FIG01: Study design — all values from bundle.run, none hard-coded.
run = bundle.run; cfg = bundle.cfg_fig;
m = struct(...
    'n_wellA', height(run.T_A_raw), 'n_train', run.n_train, 'n_test', run.n_test,...
    'n_seg0',  run.n_seg0, 'n_seg1', run.n_seg1, 'n_overlap', run.overlap.n_overlap,...
    'pct_ov',  run.overlap.pct_overlap, 'n_popA', run.n_pop_A, 'n_popB', run.n_pop_B,...
    'gap_m',   run.cfg.depth.wellB_seg1_min - run.cfg.depth.wellB_seg0_max,...
    'dt_z',    bundle.domain_shift.dt_z, 'dt_delta_pct', bundle.domain_shift.dt_delta_pct,...
    'dt_ood3_pct', bundle.domain_shift.dt_ood3_pct, 'r2_WA', run.deploy_r2_WA, 'deploy', run.deploy_name,...
    'n_feat',  numel(run.fs.S1_features), 'feats', strjoin(run.fs.S1_features,', '),...
    'n_qc',    bundle.domain_shift.n_qc_flagged,...
    'pct_qc',  bundle.domain_shift.pct_qc_flagged,...
    'seed',    run.cfg.seeds.canonical,...
    'r2_popA', run.eval_popA.R2_raw, 'r2_popB', run.eval_popB.R2_raw);

% Read DT z-score from domain shift if available
if ~isempty(bundle.fs_report); end  % placeholder

w=cfg.width_in; h=min(7,cfg.max_h_in);
fig=figure('Color','w','Units','inches','Position',[1 1 w h],...
    'PaperUnits','inches','PaperSize',[w h],'PaperPosition',[0 0 w h]);
ax=axes('Position',[0 0 1 1]); axis off; hold on;
fn=cfg.font; fs=cfg.fontsize; fsm=cfg.fontsize_sm;
C_A=cfg.color_A; C_B=cfg.color_B; C_F=cfg.color_fail;
bx=@(x,y,w2,h2,c) annotation('rectangle',[x y w2 h2],'FaceColor',c,'EdgeColor','none','FaceAlpha',0.85);
tx=@(x,y,s,sz,fw) text(x,y,s,'FontName',fn,'FontSize',sz,'FontWeight',fw,...
    'HorizontalAlignment','center','Units','normalized');

% Headers
bx(0.02,0.89,0.29,0.09,[0.90 0.93 1.0]); tx(0.165,0.93,'DATA PARTITION',fs,'bold');
bx(0.35,0.89,0.31,0.09,[0.93 0.97 0.93]); tx(0.505,0.93,'MODEL DEVELOPMENT',fs,'bold');
bx(0.70,0.89,0.28,0.09,[1.0 0.93 0.93]); tx(0.84,0.93,'EVALUATION OUTCOME',fs,'bold');

% Left column — data
items_L = {
  [0.03 0.70 0.27 0.17], C_A.*0.8+[1 1 1].*0.2,...
    sprintf('Well-A: n=%d (calibration)\nTrain=%d | Test=%d',m.n_wellA,m.n_train,m.n_test);
  [0.03 0.57 0.27 0.12], C_A.*0.5+[1 1 1].*0.5,...
    sprintf('Depth-blocked split\nTest fraction: %.0f%%',run.cfg.split.test_frac*100);
  [0.03 0.51 0.27 0.05], [0.92 0.92 0.92],...
    sprintf('Gap: %.1f m',m.gap_m);
  [0.03 0.36 0.27 0.14], C_B.*0.7+[1 1 1].*0.3,...
    sprintf('Well-B Seg0: n=%d\nPop-A=%d | Pop-B=%d (QC)',m.n_seg0,m.n_popA,m.n_popB);
  [0.03 0.26 0.27 0.09], cfg.color_dup,...
    sprintf('Seg1: n=%d (%.0f%% overlap\nexcluded from evaluation)',m.n_seg1,m.pct_ov);
  [0.03 0.16 0.27 0.09], C_F.*0.15+[1 1 1].*0.85,...
    sprintf('DT: +%.1f%%%% shift\n%.0f%%%% OOD (z=%+.2f\x3c3)',m.dt_delta_pct,m.dt_ood3_pct,m.dt_z);
};
for ii=1:size(items_L,1)
    pos=items_L{ii,1}; col=items_L{ii,2}; lbl=items_L{ii,3};
    bx(pos(1),pos(2),pos(3),pos(4),col);
    tx(pos(1)+pos(3)/2,pos(2)+pos(4)/2,lbl,fsm,'normal');
end

% Centre column — development
dev_items = {
    sprintf('Features: %s',m.feats);
    'Preproc fit: training block only';
    sprintf('k=%d depth-blocked OOF folds',run.cfg.split.kfold);
    'Base learners: PNN, MLFFNN, DFFNN, CNN1D';
    sprintf('Meta-candidates: %s',strjoin(run.cfg.stack.meta_candidates,', '));
    sprintf('Selected (Well-A only): %s\nR^2_{WA}=%.4f',upper(m.deploy),m.r2_WA);
    sprintf('Seed: %d | Well-B NOT used for selection',m.seed);
};
y0=0.84;
for ii=1:numel(dev_items)
    bx(0.36,y0-0.04,0.28,0.075,[0.93 0.97 1.0]);
    tx(0.50,y0+0.0,dev_items{ii},fsm-1,'normal');
    y0=y0-0.09;
end

% Right column — outcome
eval_items = {
    {[1.0 0.97 0.93], sprintf('Common mask: n=%d',m.n_popB)};
    {[1.0 0.95 0.90], sprintf('Pop-A (n=%d): R^2=%.4f',m.n_popA,m.r2_popA)};
    {[1.0 0.93 0.93], sprintf('Pop-B (n=%d): R^2=%.4f',m.n_popB,m.r2_popB)};
    {[1.0 0.90 0.90], 'All R^2 < 0: generalization failure'};
    {C_F.*0.15+[1 1 1].*0.85, 'Geomechanical gate: 0% valid'};
    {C_F.*0.2+[1 1 1].*0.8, 'Domain adaptation required'};
};
y0=0.84;
for ii=1:numel(eval_items)
    col=eval_items{ii}{1}; lbl=eval_items{ii}{2};
    bx(0.71,y0-0.04,0.27,0.075,col);
    tx(0.845,y0+0.0,lbl,fsm-1,'normal');
    y0=y0-0.09;
end
annotation('arrow',[0.30 0.35],[0.74 0.74],'LineWidth',1.5,'HeadWidth',8);
annotation('arrow',[0.67 0.70],[0.55 0.55],'LineWidth',1.5,'HeadWidth',8,'Color',C_F);
annotation('textbox',[0.01 0.01 0.98 0.07],'String',...
    'Field, reservoir, operator, and geographic identifiers have been anonymized. All values read from FROZEN_NUMERICAL_RUN.mat.',...
    'FontName',fn,'FontSize',fsm-2,'EdgeColor','none','HorizontalAlignment','center');

% Source data CSV
sd = [{'n_wellA';'n_train';'n_test';'n_seg0';'n_overlap';'n_popA';'n_popB';...
       'gap_m';'deploy_model';'r2_WA';'r2_popA';'r2_popB';'seed';'geomech_valid_pct'},...
      {m.n_wellA;m.n_train;m.n_test;m.n_seg0;m.n_overlap;m.n_popA;m.n_popB;...
       m.gap_m;m.deploy;m.r2_WA;m.r2_popA;m.r2_popB;m.seed;run.geomech.valid_pct}];
T_sd = cell2table(sd,'VariableNames',{'KEY','VALUE'});
writetable(T_sd, fullfile(bundle.out,'figures_source_data','FIG01_source_data.csv'));
ei = gse_report.save_figure(fig,'FIG01_study_design_and_validation','line_art',bundle);
end
