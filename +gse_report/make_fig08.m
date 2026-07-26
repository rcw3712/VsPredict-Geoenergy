function ei = make_fig08(bundle)
% FIG08: Geomechanical consequences — all values from run.geomech and geo_diag CSV.
run=bundle.run; cfg=bundle.cfg_fig; geo=bundle.geo_diag;
sqrt2=run.cfg.sanity.vpvs_min;

w=cfg.width_in; h=min(5.5,cfg.max_h_in);
fig=figure('Color','w','Units','inches','Position',[1 1 w h],...
    'PaperUnits','inches','PaperSize',[w h],'PaperPosition',[0 0 w h]);
fn=cfg.font; fsm=cfg.fontsize_sm; fs=cfg.fontsize;
C_A=cfg.color_A; C_B=cfg.color_B; C_F=cfg.color_fail;

% (a) Vp/Vs profiles
ax1=subplot(1,3,1); hold on;
% Compute Vp/Vs directly from raw data (geo_diag CSV has NU/G/K/E, not VPVS)
T_B=run.T_B_raw; seg0_m=T_B.DEPTH<=run.cfg.depth.wellB_seg0_max;
vp_seg0=T_B.VP(seg0_m); vs_m_seg0=T_B.VS(seg0_m); d_seg0=T_B.DEPTH(seg0_m);
vpvs_m=vp_seg0./vs_m_seg0;
% Predicted VS from predictions CSV
vs_p_seg0=nan(sum(seg0_m),1);
if ~isempty(bundle.pred_csv) && height(bundle.pred_csv)>0
    % pred_csv rows correspond to Pop-B mask positions (n=236)
    % Build full Seg0 vector (n=329), NaN for QC-excluded rows
    vs_p_full = nan(sum(seg0_m),1);
    popB_in_seg0 = logical(T_B.POP_B_PHYSICAL_QC(seg0_m));
    n_pred = height(bundle.pred_csv);
    n_popB = sum(popB_in_seg0);
    vs_p_full(popB_in_seg0) = bundle.pred_csv.VS_pred_raw(1:min(n_pred,n_popB));
    vs_p_seg0 = vs_p_full;
end
vpvs_p=vp_seg0./vs_p_seg0;
ok_m=~isnan(vpvs_m); ok_p=~isnan(vpvs_p);
if any(ok_m); plot(vpvs_m(ok_m),d_seg0(ok_m),'-','Color',C_A,'LineWidth',0.9,...
    'DisplayName','Measured V_P/V_S'); end
if any(ok_p); plot(vpvs_p(ok_p),d_seg0(ok_p),'--','Color',C_B,'LineWidth',0.9,...
    'DisplayName','Predicted V_P/V_S'); end
xline(sqrt2,'k--','LineWidth',1.0);
text(sqrt2+0.01,min(d_seg0)+5,sprintf('sqrt(2)=%.4f',sqrt2),'FontName',fn,'FontSize',fsm-2,'Color',[0.4 0.4 0.4]);
set(ax1,'YDir','reverse','FontName',fn,'FontSize',fsm,'Box','on','TickDir','out'); grid on;
xlabel('V_P/V_S','FontName',fn,'FontSize',fsm); ylabel('Depth (m)','FontName',fn,'FontSize',fsm);
legend('Location','best','FontSize',fsm-1,'FontName',fn);
title('(a) V_P/V_S profiles','FontName',fn,'FontSize',fs,'FontWeight','bold');

% (b) Physical gate counts
ax2=subplot(1,3,2); hold on; box on;
gm=run.geomech;
cats={'Pop-B eval','Meas Vp/Vs OK','Pred Vp/Vs OK','Pred Poisson OK'};
% Use values from run.geomech (already computed correctly in Gate 13)
n_meas_ok=sum(vpvs_m>=sqrt2&~isnan(vpvs_m));
n_pred_vpvs=gm.n_vpvs_pred_ok;
% Use full set of geomechanical gates from run struct
n_vpvs_ok = gm.n_vpvs_pred_ok;
n_nu_ok   = gm.n_nu_pred_ok;
n_all_ok  = gm.n_all_gates;
vals=[gm.n_eval, n_meas_ok, n_vpvs_ok, n_nu_ok];
bar_c={[0.6 0.7 0.8],C_A,C_B,C_F};
for bi=1:4
    bar(bi,vals(bi),0.7,'FaceColor',bar_c{bi},'EdgeColor','none','FaceAlpha',0.85);
    text(bi,vals(bi)+1,sprintf('%d',vals(bi)),'FontName',fn,'FontSize',fsm-1,...
        'HorizontalAlignment','center','FontWeight','bold');
end
set(ax2,'XTick',1:4,'XTickLabel',cats,'FontName',fn,'FontSize',fsm-1,'Box','on','TickDir','out');
ylabel('Count','FontName',fn,'FontSize',fs);
title(sprintf('(b) Physical gate\n(%.1f%% valid)',gm.valid_pct),'FontName',fn,'FontSize',fs,'FontWeight','bold');

% (c) Diagnostic
ax3=subplot(1,3,3); axis off;
msg={
    sprintf('Predicted geomech valid:');
    sprintf('%d/%d (%.1f%%)',gm.n_nu_pred_ok,gm.n_eval,gm.valid_pct);
    '';
    'No physically admissible';
    'predicted geomechanical';
    'estimates under the';
    'predefined physical gates.';
    '';
    sprintf('Bias = %+.4f km/s',run.eval_popB.bias_raw);
    sprintf('Pred VS > VP/sqrt(2)');
    'for all eval samples.';
    '';
    'Classification:';
    'PREDICTION-ERROR';
    'PROPAGATION';
};
y=0.97;
for ti=1:numel(msg)
    fw='normal'; col=[0 0 0]; sz=fsm-1;
    if ti==1; fw='bold'; sz=fsm; end
    if any(ti==[13 14 15]); fw='bold'; col=C_F; end
    text(0.5,y,msg{ti},'FontName',fn,'FontSize',sz,'FontWeight',fw,'Color',col,...
        'HorizontalAlignment','center','VerticalAlignment','top','Units','normalized');
    y=y-0.065;
end
title('(c) Diagnostic','FontName',fn,'FontSize',fs,'FontWeight','bold');

T_src=array2table(vals','VariableNames',{'Count'}); T_src.Category={'Pop-B eval';'Meas Vp/Vs ok';'Pred Vp/Vs ok';'Pred nu ok'};
writetable(T_src,fullfile(bundle.out,'figures_source_data','FIG08_geomech_gate.csv'));
ei=gse_report.save_figure(fig,'FIG08_geomechanical_consequences','combination',bundle);
end
