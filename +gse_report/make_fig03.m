function ei = make_fig03(bundle)
% FIG03: Domain shift histograms — reads from TABLE2 CSV, not hard-coded.
run=bundle.run; cfg=bundle.cfg_fig;
T2=bundle.fs_report;  % note: this is actually FEATURE_SELECTION_REPORT
% Get raw data
T_A=run.T_A_raw; T_B_seg0=run.T_B_raw(run.T_B_raw.DEPTH<=run.cfg.depth.wellB_seg0_max,:);
feats=run.cfg.data.features;
xlabs={'GR (API)','DT (us/ft)','NPHI (%)','RHOB (g/cm3)'};
panels='abcd';

w=cfg.width_in; h=min(5.5,cfg.max_h_in);
fig=figure('Color','w','Units','inches','Position',[1 1 w h],...
    'PaperUnits','inches','PaperSize',[w h],'PaperPosition',[0 0 w h]);
fn=cfg.font; fsm=cfg.fontsize_sm; fs=cfg.fontsize;

for fi=1:4
    f=feats{fi};
    ax=subplot(2,2,fi); hold on;
    if ~ismember(f,T_A.Properties.VariableNames); axis off; continue; end
    a=T_A.(f); b=T_B_seg0.(f);
    both=[a(:);b(:)]; blo=min(both,[],'omitnan'); bhi=max(both,[],'omitnan');
    edges=linspace(blo,bhi,35);
    histogram(a,'BinEdges',edges,'Normalization','probability',...
        'FaceColor',cfg.color_A,'FaceAlpha',0.65,'EdgeColor','none');
    histogram(b,'BinEdges',edges,'Normalization','probability',...
        'FaceColor',cfg.color_B,'FaceAlpha',0.65,'EdgeColor','none');
    mu_a=mean(a,'omitnan'); mu_b=mean(b,'omitnan');
    sg_a=std(a,'omitnan');
    z_mu=(mu_b-mu_a)/sg_a;
    ood_pct=sum(abs((b-mu_a)/sg_a)>3)/numel(b)*100;
    xline(mu_a,'--','Color',cfg.color_A,'LineWidth',1.0);
    xline(mu_b,'--','Color',cfg.color_B,'LineWidth',1.0);
    set(ax,'FontName',fn,'FontSize',fsm,'Box','on','TickDir','out'); grid on;
    xlabel(xlabs{fi},'FontName',fn,'FontSize',fsm);
    ylabel('Probability','FontName',fn,'FontSize',fsm);
    xl=xlim; yl=ylim;
    text(xl(2)-0.02*diff(xl),yl(2)-0.03*diff(yl),...
        sprintf('z(muB)=%+.2f\nOOD_{|z|>3}=%.1f%%',z_mu,ood_pct),...
        'FontName',fn,'FontSize',fsm-2,'HorizontalAlignment','right','VerticalAlignment','top',...
        'BackgroundColor',[1 1 1 0.7]);
    text(xl(1)+0.03*diff(xl),yl(2)-0.03*diff(yl),sprintf('(%s)',panels(fi)),...
        'FontName',fn,'FontSize',fs,'FontWeight','bold','VerticalAlignment','top');
    if fi==1
        legend({'Well-A (calibration)','Well-B Seg0 (blind)'},...
            'Location','best','FontSize',fsm-1,'FontName',fn);
    end
end
ei=gse_report.save_figure(fig,'FIG03_domain_shift','combination',bundle);
writetable(T_A(:,intersect(feats,T_A.Properties.VariableNames,'stable')),...
    fullfile(bundle.out,'figures_source_data','FIG03_WellA_raw.csv'));
writetable(T_B_seg0(:,intersect(feats,T_B_seg0.Properties.VariableNames,'stable')),...
    fullfile(bundle.out,'figures_source_data','FIG03_WellB_Seg0_raw.csv'));
end