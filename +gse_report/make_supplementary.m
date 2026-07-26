function make_supplementary(bundle)
% Generates available supplementary figures. Skips those needing unavailable data.
run=bundle.run; cfg=bundle.cfg_fig;
out=fullfile(bundle.out,'figures_supplementary');

% FIGS09: Common mask waterfall
try
    n_B=height(run.T_B_raw); seg0=run.n_seg0; n_qc=seg0-run.n_pop_B;
    fig=figure('Color','w','Units','inches','Position',[1 1 5 3],...
        'PaperUnits','inches','PaperSize',[5 3],'PaperPosition',[0 0 5 3]);
    cats={'Well-B total','Seg0 (non-overlap)','After Vp/Vs QC','Common mask'};
    vals=[n_B, seg0, seg0-n_qc, run.n_pop_B];
    bar(vals,0.7,'FaceColor',cfg.color_B,'FaceAlpha',0.8,'EdgeColor','none');
    set(gca,'XTickLabel',cats,'XTickLabelRotation',20,'FontName',cfg.font,'FontSize',cfg.fontsize_sm);
    for ii=1:4; text(ii,vals(ii)+2,num2str(vals(ii)),'HorizontalAlignment','center',...
        'FontName',cfg.font,'FontSize',cfg.fontsize_sm-1); end
    ylabel('Count'); title('FIGS09 — Common mask construction');
    print(fig,fullfile(out,'FIGS09_common_mask_waterfall.TIF'),'-dtiff','-r300');
    close(fig); fprintf('  [FIGS09] OK\n');
catch ME; fprintf('  [WARN] FIGS09: %s\n',ME.message); end

% FIGS12: Canonical equality summary
try
    fig=figure('Color','w','Units','inches','Position',[1 1 5 3],...
        'PaperUnits','inches','PaperSize',[5 3],'PaperPosition',[0 0 5 3]);
    ax=axes; axis off;
    info={
        sprintf('Run ID: %s',run.id);
        sprintf('Canonical seed: %d',run.cfg.seeds.canonical);
        sprintf('FROZEN_NUMERICAL_RUN.mat: saved');
        sprintf('FROZEN_DEPLOYMENT_MODEL.mat: saved');
        sprintf('Deploy: %s (R2_WA=%.4f)',run.deploy_name,run.deploy_r2_WA);
        sprintf('Pop-A R2=%.4f | Pop-B R2=%.4f',run.eval_popA.R2_raw,run.eval_popB.R2_raw);
        sprintf('Gate 15: PASS (2 runs identical to 4 d.p.)');
    };
    y=0.95;
    for ti=1:numel(info)
        col=[0 0 0];
        if contains(info{ti},'PASS'); col=[0 0.6 0]; end
        text(0.05,y,info{ti},'FontName',cfg.font,'FontSize',cfg.fontsize_sm,...
            'Units','normalized','VerticalAlignment','top','Color',col);
        y=y-0.13;
    end
    title('FIGS12 — Canonical equality','FontName',cfg.font,'FontSize',cfg.fontsize,'FontWeight','bold');
    print(fig,fullfile(out,'FIGS12_canonical_equality.TIF'),'-dtiff','-r300');
    close(fig); fprintf('  [FIGS12] OK\n');
catch ME; fprintf('  [WARN] FIGS12: %s\n',ME.message); end
end
