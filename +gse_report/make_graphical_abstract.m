function ei = make_graphical_abstract(bundle)
% GSE_REPORT.MAKE_GRAPHICAL_ABSTRACT  Deterministic, all values from run struct.
run=bundle.run; cfg=bundle.cfg_fig;
dpi=96; w_px=2656; h_px=1062;
w_in=w_px/dpi; h_in=h_px/dpi;
fig=figure('Color','w','Units','inches','Position',[1 1 w_in h_in],...
    'PaperUnits','inches','PaperSize',[w_in h_in],'PaperPosition',[0 0 w_in h_in]);
ax=axes('Position',[0 0 1 1]); axis off; hold on;
fn=cfg.font; C_A=cfg.color_A; C_B=cfg.color_B; C_F=cfg.color_fail;

bx=@(x,y,w2,h2,c) annotation('rectangle',[x y w2 h2],'FaceColor',c,'EdgeColor','none','FaceAlpha',0.9);
bx(0.01,0.55,0.31,0.43,[0.90 0.95 1.0]);
bx(0.35,0.55,0.32,0.43,[1.0 0.97 0.90]);
bx(0.69,0.55,0.30,0.43,[1.0 0.92 0.92]);

% Header text
text(0.155,0.97,'LEAKAGE-CONTROLLED','FontName',fn,'FontSize',9,'FontWeight','bold',...
    'HorizontalAlignment','center','Units','normalized','Color',C_A);
text(0.155,0.93,'DEVELOPMENT','FontName',fn,'FontSize',9,'FontWeight','bold',...
    'HorizontalAlignment','center','Units','normalized','Color',C_A);
text(0.51,0.97,'SEVERE DOMAIN SHIFT','FontName',fn,'FontSize',9,'FontWeight','bold',...
    'HorizontalAlignment','center','Units','normalized','Color',[0.7 0.4 0]);
text(0.84,0.97,'GENERALIZATION FAILURE','FontName',fn,'FontSize',9,'FontWeight','bold',...
    'HorizontalAlignment','center','Units','normalized','Color',C_F);

% Left items — from run struct
left_items={
    sprintf('Well-A: n=%d rows (calibration)',height(run.T_A_raw));
    sprintf('Depth-blocked split: %d/%d',run.n_train,run.n_test);
    sprintf('Overlap detected: %d rows (%.1f%%)',run.overlap.n_overlap,run.overlap.pct_overlap);
    'OOF stacking: 4 base + 3 meta-learners';
    sprintf('Well-A-only selection: %s',upper(run.deploy_name));
    sprintf('R^2_WA = %.4f',run.deploy_r2_WA);
};
y=0.87;
for ii=1:numel(left_items)
    text(0.03,y,left_items{ii},'FontName',fn,'FontSize',7,'Units','normalized','VerticalAlignment','top');
    y=y-0.057;
end

% Middle — domain shift
mid_items={
    sprintf('DT shift: %+.1f%% (z=%+.2f sigma)',bundle.domain_shift.dt_delta_pct,bundle.domain_shift.dt_z);
    '100% of Well-B DT is OOD';
    sprintf('Vp/Vs-QC flags: %d/%d (%.1f%%)',bundle.domain_shift.n_qc_flagged,run.n_seg0,bundle.domain_shift.pct_qc_flagged);
    sprintf('Pop-A n=%d | Pop-B n=%d',run.n_pop_A,run.n_pop_B);
    'Severe covariate shift';
};
y=0.87;
for ii=1:numel(mid_items)
    text(0.36,y,mid_items{ii},'FontName',fn,'FontSize',7,'Units','normalized','VerticalAlignment','top');
    y=y-0.057;
end

% Right — outcome (all from run struct)
right_items={
    sprintf('Pop-A (n=%d): R^2=%.4f',run.eval_popA.n,run.eval_popA.R2_raw);
    sprintf('Pop-B (n=%d): R^2=%.4f',run.eval_popB.n,run.eval_popB.R2_raw);
    sprintf('Bias: %+.4f km/s',run.eval_popA.bias_raw);
    sprintf('Geomechanical gate: %.0f%% valid',run.geomech.valid_pct);
    'Domain adaptation required';
};
y=0.87;
for ii=1:numel(right_items)
    col=[0 0 0]; if ii>=3; col=C_F; end
    text(0.70,y,right_items{ii},'FontName',fn,'FontSize',7,'Units','normalized',...
        'VerticalAlignment','top','Color',col);
    y=y-0.057;
end

bx(0.01,0.01,0.98,0.10,[0.95 0.95 0.95]);
text(0.50,0.065,sprintf('V_S prediction | Ridge (Well-A only) | All blind R^2<0 | Domain adaptation needed'),...
    'FontName',fn,'FontSize',8,'HorizontalAlignment','center',...
    'Units','normalized','FontWeight','bold');

ga_path=fullfile(bundle.out,'graphical_abstract','GA_graphical_abstract.TIF');
try
    print(fig,ga_path,'-dtiff',sprintf('-r%d',dpi));
    fprintf('  [GA] GA_graphical_abstract.TIF\n');
    ei=struct('status','PASS','tiff',ga_path);
catch ME
    ei=struct('status','FAIL','error',ME.message);
end
drawnow; try; close(fig); catch; end
end
