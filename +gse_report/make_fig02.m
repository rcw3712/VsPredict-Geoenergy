function ei = make_fig02(bundle)
% FIG02: Well-log depth tracks (full Well-A and full Well-B).
run=bundle.run; cfg=bundle.cfg_fig;
T_A=run.T_A_raw; T_B=run.T_B_raw;
logs={'GR','DT','NPHI','RHOB','VS'};
xlabs={'GR (API)','DT (us/ft)','NPHI (%)','RHOB (g/cm3)','V_S (km/s)'};
seg0_max=run.cfg.depth.wellB_seg0_max;
seg1_min=run.cfg.depth.wellB_seg1_min;
vpvs_min=run.cfg.sanity.vpvs_min;
tr_max=run.T_A_raw.DEPTH(run.n_train);

w=cfg.width_in; h=min(9,cfg.max_h_in);
fig=figure('Color','w','Units','inches','Position',[1 1 w h],...
    'PaperUnits','inches','PaperSize',[w h],'PaperPosition',[0 0 w h]);
fn=cfg.font; fsm=cfg.fontsize_sm;

for wi=1:2
    if wi==1; T=T_A; col=cfg.color_A; lbl='Well-A (calibration)';
    else;      T=T_B; col=cfg.color_B; lbl='Well-B (blind)'; end
    for li=1:5
        subplot(2,5,(wi-1)*5+li); hold on; box on; grid on;
        if ~ismember(logs{li},T.Properties.VariableNames); axis off; continue; end
        v=T.(logs{li}); d=T.DEPTH;
        if wi==2
            s0=d<=seg0_max; s1=d>=seg1_min;
            if any(s0); plot(v(s0),d(s0),'-','Color',col,'LineWidth',cfg.lw); end
            if any(s1); plot(v(s1),d(s1),'-','Color',cfg.color_dup,'LineWidth',cfg.lw*0.7); end
            if strcmp(logs{li},'VS') && ismember('VPVS',T.Properties.VariableNames)
                qc=s0 & T.VPVS<vpvs_min & ~isnan(v);
                if any(qc); scatter(v(qc),d(qc),10,'r','o','MarkerFaceAlpha',0.5); end
            end
        else
            plot(v,d,'-','Color',col,'LineWidth',cfg.lw);
            yline(tr_max,'--','Color',[0.5 0.5 0.5],'LineWidth',0.75,'Alpha',0.7);
        end
        set(gca,'YDir','reverse','FontName',fn,'FontSize',fsm,'TickDir','out');
        xlabel(xlabs{li},'FontName',fn,'FontSize',fsm);
        if li==1; ylabel(sprintf('%s\nDepth (m)',lbl),'FontName',fn,'FontSize',fsm,'FontWeight','bold');
        else; set(gca,'YTickLabel',[]); end
    end
end
annotation('textbox',[0.01 0.01 0.98 0.05],'String',...
    sprintf('Blue:Well-A | Red:Well-B Seg0 | Grey:Seg1 (n=%d overlap) | Red dots:Vp/Vs-QC flags (n=93) | Dashed:train/test boundary',...
    run.n_seg1),'FontName',fn,'FontSize',fsm-2,'EdgeColor','none','HorizontalAlignment','center');
ei=gse_report.save_figure(fig,'FIG02_well_logs_and_qc','combination',bundle);
end