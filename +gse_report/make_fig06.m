function ei = make_fig06(bundle)
% FIG06: Canonical blind-well evaluation.
%   All metrics read from run.eval_popB (Pop-B, physical QC).
%   Predictions read from predictions_WellB_v4.csv.
run=bundle.run; cfg=bundle.cfg_fig;
pred=bundle.pred_csv;
if isempty(pred)||height(pred)==0; ei=struct('status','FAIL'); return; end

% Use Pop-B mask
pop_B=logical(pred.POP_B_MASK);
vs_m=pred.VS_measured(pop_B); vs_p=pred.VS_pred_raw(pop_B);
d_eval=pred.DEPTH(pop_B);

% Metrics from run struct (authoritative — NOT recomputed)
m=run.eval_popB;

w=cfg.width_in; h=min(4.5,cfg.max_h_in);
fig=figure('Color','w','Units','inches','Position',[1 1 w h],...
    'PaperUnits','inches','PaperSize',[w h],'PaperPosition',[0 0 w h]);
fn=cfg.font; fsm=cfg.fontsize_sm; fs=cfg.fontsize;
C_A=cfg.color_A; C_B=cfg.color_B;
vs_r=[min(vs_m)*0.87, max(vs_m)*1.09];

% (a) Crossplot
ax1=subplot(1,3,1); hold on;
scatter(vs_m,vs_p,15,C_A,'filled','MarkerFaceAlpha',0.6);
plot(vs_r,vs_r,'k-','LineWidth',1.3);
plot(vs_r,vs_r+m.RMSE_raw,'--','Color',[0.6 0.6 0.6],'LineWidth',0.8);
plot(vs_r,vs_r-m.RMSE_raw,'--','Color',[0.6 0.6 0.6],'LineWidth',0.8);
set(ax1,'FontName',fn,'FontSize',fsm,'Box','on','TickDir','out','XLim',vs_r,'YLim',vs_r); grid on;
xlabel('V_S measured (km/s)','FontName',fn,'FontSize',fsm);
ylabel('V_S predicted (km/s)','FontName',fn,'FontSize',fsm);
xl=xlim; yl=ylim;
text(xl(1)+0.04*diff(xl),yl(2)-0.02*diff(yl),'(a)','FontName',fn,'FontSize',fs,...
    'FontWeight','bold','VerticalAlignment','top');
text(xl(2)-0.03*diff(xl),yl(1)+0.08*diff(yl),...
    sprintf('%s\nR^2=%.4f\nRMSE=%.4f km/s\nn=%d\nseed=%d',...
    upper(run.deploy_name),m.R2_raw,m.RMSE_raw,m.n,run.cfg.seeds.canonical),...
    'FontName',fn,'FontSize',fsm-2,'HorizontalAlignment','right');

% (b) Residual vs depth
ax2=subplot(1,3,2); hold on;
resid=vs_p-vs_m;
plot(resid,d_eval,'.','Color',C_B,'MarkerSize',4);
xline(0,'k--','LineWidth',1.0);
set(ax2,'YDir','reverse','FontName',fn,'FontSize',fsm,'Box','on','TickDir','out'); grid on;
xlabel('Residual (km/s)','FontName',fn,'FontSize',fsm);
ylabel('Depth (m)','FontName',fn,'FontSize',fsm);
xl=xlim; yl=ylim;
text(xl(1)+0.04*diff(xl),yl(1)+0.03*diff(yl),'(b)','FontName',fn,'FontSize',fs,'FontWeight','bold');
title('Residual = pred - meas','FontName',fn,'FontSize',fsm-1);

% (c) Residual histogram
ax3=subplot(1,3,3); hold on;
histogram(resid,30,'FaceColor',C_A,'FaceAlpha',0.75,'EdgeColor','none');
xline(0,'k-','LineWidth',1.2);
xline(m.bias_raw,'--','Color',C_B,'LineWidth',1.0);
set(ax3,'FontName',fn,'FontSize',fsm,'Box','on','TickDir','out'); grid on;
xlabel('Residual (km/s)','FontName',fn,'FontSize',fsm);
ylabel('Count','FontName',fn,'FontSize',fsm);
xl=xlim; yl=ylim;
text(xl(1)+0.04*diff(xl),yl(2)-0.02*diff(yl),'(c)','FontName',fn,'FontSize',fs,...
    'FontWeight','bold','VerticalAlignment','top');
text(xl(2)-0.03*diff(xl),yl(2)-0.05*diff(yl),...
    sprintf('Bias=%+.4f km/s\nMAE=%.4f km/s',m.bias_raw,m.MAE_raw),...
    'FontName',fn,'FontSize',fsm-2,'HorizontalAlignment','right','VerticalAlignment','top');

% Source data
T_src=table(d_eval,vs_m,vs_p,resid,'VariableNames',{'DEPTH','VS_measured','VS_pred_raw','Residual'});
writetable(T_src,fullfile(bundle.out,'figures_source_data','FIG06_blind_eval.csv'));
ei=gse_report.save_figure(fig,'FIG06_blind_well_evaluation','combination',bundle);
end
