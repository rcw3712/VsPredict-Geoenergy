function ei = make_fig07(bundle)
% FIG07: Cross-domain diagnostics — all values from registry.
run=bundle.run; cfg=bundle.cfg_fig; reg=bundle.registry;

w=cfg.width_in; h=min(5.5,cfg.max_h_in);
fig=figure('Color','w','Units','inches','Position',[1 1 w h],...
    'PaperUnits','inches','PaperSize',[w h],'PaperPosition',[0 0 w h]);
fn=cfg.font; fsm=cfg.fontsize_sm; fs=cfg.fontsize;

% Sort registry by Pop-B R² descending
r2_all=arrayfun(@(r) r.r2_popB, reg);
[~,ord]=sort(r2_all,'descend');
names_s={reg(ord).name}; r2_s=r2_all(ord); bias_s=arrayfun(@(r) r.bias_popB,reg(ord));

% (a) Bias chart
ax1=subplot(1,2,1); hold on; box on; grid on;
n_m=numel(names_s);
for mi=1:n_m
    col=[0.75 0.80 0.87];
    if strcmp(reg(ord(mi)).model_type,'empirical'); col=cfg.color_emp; end
    if reg(ord(mi)).is_deployed; col=cfg.color_dep; end
    if strcmp(reg(ord(mi)).model_type,'baseline'); col=[0.6 0.6 0.6]; end
    bar(mi,bias_s(mi),0.65,'FaceColor',col,'EdgeColor','none','FaceAlpha',0.85);
end
yline(0,'k-','LineWidth',1.0);
set(ax1,'XTick',1:n_m,'XTickLabel',strrep(names_s,'_',' '),'XTickLabelRotation',45,...
    'FontName',fn,'FontSize',fsm-1,'Box','on','TickDir','out');
ylabel('Bias = predicted - measured (km/s)','FontName',fn,'FontSize',fs);
title(sprintf('(a) Prediction bias (Pop-B, n=%d)',run.eval_popB.n),'FontName',fn,'FontSize',fs,'FontWeight','bold');

% (b) R² scatter: Well-A vs blind
ax2=subplot(1,2,2); hold on; box on; grid on;
meta_names=run.cfg.stack.meta_candidates;
for mi=1:numel(meta_names)
    nm=meta_names{mi};
    idx=find(strcmpi({reg.name},nm),1);
    if isempty(idx); continue; end
    key=strrep(nm,'_stacker','');
    r2_wa=NaN;
    if isfield(run.meta_metrics,key); r2_wa=run.meta_metrics.(key).R2_te; end
    r2_bl=reg(idx).r2_popB;
    col=[0.75 0.80 0.87];
    if reg(idx).is_deployed; col=cfg.color_dep; end
    if ~isnan(r2_wa)&&~isnan(r2_bl)
        scatter(r2_wa,r2_bl,70,col,'filled','MarkerFaceAlpha',0.85);
        text(r2_wa+0.02,r2_bl,strrep(nm,'_',' '),'FontName',fn,'FontSize',fsm-2);
    end
end
yline(0,'k--','LineWidth',1.0,'Label','R^2=0');
xlabel('R^2 Well-A internal test','FontName',fn,'FontSize',fs);
ylabel('R^2 Well-B blind Pop-B','FontName',fn,'FontSize',fs);
title('(b) Internal vs blind (meta-learners)','FontName',fn,'FontSize',fs,'FontWeight','bold');
text(0.5,0.05,'All blind R^2<0 — GENERALIZATION FAILURE',...
    'HorizontalAlignment','center','FontName',fn,'FontSize',fsm-1,...
    'Color',cfg.color_fail,'FontWeight','bold');

T_src=table(names_s(:),r2_s(:),bias_s(:),'VariableNames',{'MODEL','R2_PopB','BIAS_PopB'});
writetable(T_src,fullfile(bundle.out,'figures_source_data','FIG07_diagnostics.csv'));
ei=gse_report.save_figure(fig,'FIG07_cross_domain_diagnostics','combination',bundle);
end
