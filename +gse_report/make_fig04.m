function ei = make_fig04(bundle)
% FIG04: OOF fold metrics + meta-learner Well-A selection.
%   All values from run.oof_metrics_canonical and run.meta_metrics.
run=bundle.run; cfg=bundle.cfg_fig;
oof_csv=bundle.oof_folds;  % OOF_fold_metrics.csv

w=cfg.width_in; h=min(5.5,cfg.max_h_in);
fig=figure('Color','w','Units','inches','Position',[1 1 w h],...
    'PaperUnits','inches','PaperSize',[w h],'PaperPosition',[0 0 w h]);
fn=cfg.font; fsm=cfg.fontsize_sm; fs=cfg.fontsize;
seed42=run.cfg.seeds.canonical;

% (a) OOF heatmap (base learners × folds, canonical seed)
ax1=subplot(1,2,1); hold on;
if ~isempty(oof_csv) && height(oof_csv)>0
    T42=oof_csv(oof_csv.SEED==seed42,:);
    base_names={'pnn','mlffnn','dffnn','cnn1d'};
    base_disp={'PNN','MLFFNN','DFFNN','CNN1D'};
    k=run.n_folds;
    M=nan(numel(base_names),k);
    for bi=1:numel(base_names)
        rows=T42(strcmpi(T42.MODEL,base_names{bi}),:);
        for fi=1:min(height(rows),k); M(bi,rows.FOLD(fi))=rows.R2_OOF(fi); end
    end
    imagesc(M); colormap(ax1,bluewhitered_simple());
    for bi=1:numel(base_names); for fi=1:k
        if ~isnan(M(bi,fi)); text(fi,bi,sprintf('%.2f',M(bi,fi)),'FontName',fn,...
            'FontSize',fsm-2,'HorizontalAlignment','center','Color','k'); end
    end; end
    set(ax1,'YTick',1:numel(base_names),'YTickLabel',base_disp,...
        'XTick',1:k,'XTickLabel',arrayfun(@(x) sprintf('F%d',x),1:k,'UniformOutput',false),...
        'FontName',fn,'FontSize',fsm,'TickDir','out');
    colorbar(ax1,'FontName',fn,'FontSize',fsm-1);
    title(sprintf('(a) OOF R^2 (seed=%d, k=%d)',seed42,k),'FontName',fn,'FontSize',fs,'FontWeight','bold');
    xlabel('Fold','FontName',fn,'FontSize',fsm);
else; axis off; text(0.5,0.5,'OOF data not available','Units','normalized','HorizontalAlignment','center'); end

% (b) Meta-learner Well-A test R² (from run.meta_metrics)
ax2=subplot(1,2,2); hold on; box on; grid on;
meta_names=run.cfg.stack.meta_candidates;
meta_disp=strrep(meta_names,'_stacker',' stacker');
r2_vals=nan(numel(meta_names),1);
for mi=1:numel(meta_names)
    key=strrep(meta_names{mi},'_stacker','');
    if isfield(run.meta_metrics,key) && isfield(run.meta_metrics.(key),'R2_te')
        r2_vals(mi)=run.meta_metrics.(key).R2_te;
    end
end
cols_bar=repmat([0.75 0.80 0.87],numel(meta_names),1);
for mi=1:numel(meta_names)
    if strcmpi(meta_names{mi},run.deploy_name); cols_bar(mi,:)=cfg.color_dep; end
    bar(mi,r2_vals(mi),0.65,'FaceColor',cols_bar(mi,:),'EdgeColor','none','FaceAlpha',0.85);
    text(mi,r2_vals(mi)+0.1,sprintf('%.4f',r2_vals(mi)),'FontName',fn,'FontSize',fsm-1,...
        'HorizontalAlignment','center');
end
yline(0,'k--','LineWidth',1.0);
set(ax2,'XTick',1:numel(meta_names),'XTickLabel',meta_disp,'XTickLabelRotation',20,...
    'FontName',fn,'FontSize',fsm,'Box','on','TickDir','out');
ylabel('R^2 (Well-A internal test)','FontName',fn,'FontSize',fs);
title('(b) Meta-learner selection (Well-A only)','FontName',fn,'FontSize',fs,'FontWeight','bold');
text(0.5,0.05,sprintf('Selected: %s (R^2=%.4f)',run.deploy_name,run.deploy_r2_WA),...
    'Units','normalized','HorizontalAlignment','center','FontName',fn,'FontSize',fsm,...
    'Color',cfg.color_dep,'FontWeight','bold');

ei=gse_report.save_figure(fig,'FIG04_model_development_and_selection','combination',bundle);
writetable(table(meta_names(:),r2_vals,'VariableNames',{'MODEL','R2_WA_test'}),...
    fullfile(bundle.out,'figures_source_data','FIG04_meta_selection.csv'));
end

function C = bluewhitered_simple()
n=64; C=zeros(n,3);
for i=1:n
    t=(i-1)/(n-1)*2-1;
    if t<0; C(i,:)=[1+t, 1+t, 1]; else; C(i,:)=[1, 1-t, 1-t]; end
end
end
