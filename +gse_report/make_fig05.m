function ei = make_fig05(bundle)
% FIG05: Multi-seed consistency (single seed available — shows canonical).
run=bundle.run; cfg=bundle.cfg_fig;
w=cfg.width_in; h=min(4.0,cfg.max_h_in);
fig=figure('Color','w','Units','inches','Position',[1 1 w h],...
    'PaperUnits','inches','PaperSize',[w h],'PaperPosition',[0 0 w h]);
fn=cfg.font; fsm=cfg.fontsize_sm; fs=cfg.fontsize;
ax=axes; axis off;
info={
    sprintf('Canonical seed: %d',run.cfg.seeds.canonical);
    sprintf('Deploy model: %s',upper(run.deploy_name));
    sprintf('Well-A R2 = %.4f',run.deploy_r2_WA);
    sprintf('Blind Pop-A R2 = %.4f',run.eval_popA.R2_raw);
    sprintf('Blind Pop-B R2 = %.4f',run.eval_popB.R2_raw);
    '';
    'GATE_15 Cross-run reproducibility:';
    '20/20 metrics IDENTICAL across 2 runs';
    'See GATE15_CROSS_RUN_REPRODUCIBILITY_REPORT.md';
    '';
    'GATE_10 Multi-seed aggregation:';
    'OOF computed for seeds 7, 42, 123';
    'Aggregation stub — full results pending';
};
y=0.97;
for ti=1:numel(info)
    col=[0 0 0]; fw='normal';
    if contains(info{ti},'GATE_15') || contains(info{ti},'IDENTICAL'); col=[0 0.6 0]; fw='bold'; end
    if contains(info{ti},'Canonical') || contains(info{ti},'Deploy'); col=cfg.color_dep; fw='bold'; end
    text(0.05,y,info{ti},'FontName',fn,'FontSize',fsm,'Units','normalized',...
        'VerticalAlignment','top','Color',col,'FontWeight',fw);
    y=y-0.075;
end
title('FIG05 — Canonical consistency and multi-seed status',...
    'FontName',fn,'FontSize',fs,'FontWeight','bold');
ei=gse_report.save_figure(fig,'FIG05_multiseed_and_consistency','combination',bundle);
end
