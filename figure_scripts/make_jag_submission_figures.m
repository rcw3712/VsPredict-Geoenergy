function make_jag_submission_figures(analysis_root, output_root)
% Regenerate JAG Figures 1, 2 and 6 from frozen, row-level artifacts.
% This script performs plotting only; it does not refit or score any model.

repo_root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 1 || isempty(analysis_root), analysis_root = repo_root; end
if nargin < 2 || isempty(output_root)
    output_root = fullfile(repo_root,'figures','jag-submission-20261007');
end
root = analysis_root;
pkg  = output_root;
out  = output_root;
if ~isfolder(out), mkdir(out); end

assert(isfile(fullfile(root,'data','Well-A.xlsx')), ...
    ['Authorized Well-A input was not found. Pass the full private analysis ' ...
     'root as the first argument; proprietary logs are not distributed.']);
assert(isfile(fullfile(root,'data','Well-B.xlsx')), ...
    ['Authorized Well-B input was not found. Pass the full private analysis ' ...
     'root as the first argument; proprietary logs are not distributed.']);

make_fig1(root,pkg,out);
make_fig2(pkg,out);
make_fig6(root,pkg,out);
fprintf('JAG submission figures regenerated: Fig1, Fig2, Fig6.\n');
end

function make_fig1(root,pkg,out)
TA = readtable(fullfile(root,'data','Well-A.xlsx'),'VariableNamingRule','preserve');
TB = readtable(fullfile(root,'data','Well-B.xlsx'),'VariableNamingRule','preserve');
TA.Properties.VariableNames = cellfun(@(s) strtok(strtrim(s),' '),TA.Properties.VariableNames,'UniformOutput',false);
TB.Properties.VariableNames = cellfun(@(s) strtok(strtrim(s),' '),TB.Properties.VariableNames,'UniformOutput',false);
TA = sortrows(TA,'DEPTH'); TB = sortrows(TB,'DEPTH');
if ~ismember('VS',TA.Properties.VariableNames), TA.VS=304.8./TA.DTS; end
if ~ismember('VS',TB.Properties.VariableNames), TB.VS=304.8./TB.DTS; end
TA.ROW_ID=(1:height(TA))'; TB.ROW_ID=(1:height(TB))';

R = readtable(fullfile(root,'runs','run_PED_corrected_20260910_071523', ...
    '01_data_audit','DATA_ROLE_ROW_IDS.csv'),'TextType','string');
ids = @(role) R.ROW_ID(R.ROLE==role);
dev=ids("Well-A development"); holdIds=ids("Well-A holdout");
dup=ids("Well-B duplicate"); pb=ids("Pop-B diagnostic QC");
pa0=ids("Pop-A primary blind"); pa=unique([pa0;pb]);
assert(numel(dev)==392 && numel(holdIds)==100 && numel(dup)==163 && numel(pa)==329 && numel(pb)==236);

tracks={'GR','DT','NPHI','RHOB','VS'};
units={'API','\mus/ft','%','g/cm^3','km/s'};
lims=zeros(5,2);
for j=1:5
    v=[TA.(tracks{j});TB.(tracks{j})]; v=v(isfinite(v));
    d=max(v)-min(v); if d==0,d=1;end
    lims(j,:)=[min(v)-.04*d,max(v)+.04*d];
end

blue=[0.16 .42 .64]; purple=[.48 .45 .91]; orange=[.88 .32 .18];
gray=[.66 .66 .66]; peach=[.98 .63 .37];
f=figure('Visible','off','Color','w','Units','centimeters','Position',[0 0 18 21.5]);
t=tiledlayout(f,2,5,'TileSpacing','compact','Padding','compact');
for row=1:2
    T=TA; if row==2,T=TB;end
    for j=1:5
        ax=nexttile(t,(row-1)*5+j); hold(ax,'on');
        x=T.(tracks{j}); z=T.DEPTH; ok=isfinite(x)&isfinite(z);
        if row==1
            ih=ismember(T.ROW_ID,holdIds);
            plot(ax,x(ok&~ih),z(ok&~ih),'Color',blue,'LineWidth',.8);
            plot(ax,x(ok&ih),z(ok&ih),'Color',purple,'LineWidth',.8);
            yline(ax,min(z(ih)),'--','Color',[.35 .35 .35],'LineWidth',.7);
        else
            id=ismember(T.ROW_ID,dup); ia=ismember(T.ROW_ID,pa); ib=ismember(T.ROW_ID,pb);
            plot(ax,x(ok&ia),z(ok&ia),'Color',orange,'LineWidth',.8);
            plot(ax,x(ok&id),z(ok&id),'Color',gray,'LineWidth',.65);
            if j==5, scatter(ax,x(ok&ib),z(ok&ib),6,peach,'filled'); end
        end
        set(ax,'YDir','reverse','FontName','Arial','FontSize',7.4,'TickDir','out', ...
            'Box','off','XGrid','on','YGrid','on','XLim',lims(j,:));
        xlabel(ax,sprintf('%s (%s)',strrep(tracks{j},'VS','V_s'),units{j}),'FontSize',7.5);
        if j==1, ylabel(ax,'Depth (m)','FontSize',7.5); end
        if row==1 && j==1
            tt=title(ax,'(a) Well-A calibration','FontWeight','bold','FontSize',8.5);
            tt.Units='normalized'; tt.Position=[0.5 1.035 0];
        end
        if row==2 && j==1
            tt=title(ax,'(b) Well-B external evaluation','FontWeight','bold','FontSize',8.5);
            tt.Units='normalized'; tt.Position=[0.5 1.035 0];
        end
    end
end
h=[plot(nan,nan,'Color',blue,'LineWidth',1.2),plot(nan,nan,'Color',purple,'LineWidth',1.2), ...
   plot(nan,nan,'Color',orange,'LineWidth',1.2),plot(nan,nan,'Color',gray,'LineWidth',1.0), ...
   scatter(nan,nan,10,peach,'filled'),plot(nan,nan,'--','Color',[.35 .35 .35])];
lg=legend(h,{'Well-A development (n=392)','Well-A contiguous holdout (n=100)', ...
    'Well-B record-disjoint Pop-A (n=329)','Exact duplicated records excluded (n=163)', ...
    'Target-informed Pop-B (n=236)','Development/holdout boundary'}, ...
    'Location','southoutside','Orientation','horizontal','NumColumns',3,'Box','off','FontSize',6.8);
lg.Layout.Tile='south';
exportgraphics(f,fullfile(pkg,'JAG_Fig1_well_logs_qc.png'),'Resolution',300);
exportgraphics(f,fullfile(out,'Fig1.tif'),'Resolution',300);
close(f);
end

function make_fig2(pkg,out)
f=figure('Visible','off','Color','w','Units','centimeters','Position',[0 0 18 10.5]);
ax=axes(f,'Position',[.012 .075 .976 .875],'Visible','off','XLim',[0 1],'YLim',[0 1]); hold(ax,'on');
blue=[.89 .94 .99]; green=[.90 .97 .90]; red=[.99 .92 .90]; gray=[.95 .95 .96];
edge=[.52 .52 .52];
hdr(.12,'WELL-A',[.08 .25 .56]); hdr(.37,'WELL-B',[.08 .25 .56]);
hdr(.62,'MODEL DEVELOPMENT',[.05 .38 .10]); hdr(.87,'EXTERNAL EVALUATION',[.55 .10 .08]);
bx(.012,.78,.218,.11,{'Calibration well','n = 492'},blue,false);
bx(.012,.60,.218,.11,{'Development interval','n = 392'},blue,false);
bx(.012,.42,.218,.11,{'Contiguous holdout','n = 100 | R^2 = 0.3591'},gray,true);
bx(.262,.78,.218,.11,{'External well','n = 492'},blue,false);
bx(.262,.60,.218,.11,{'Exact-copy audit','163 records excluded'},red,false);
bx(.262,.42,.218,.11,{'Record-disjoint Pop-A','n = 329'},blue,true);
bx(.262,.24,.218,.11,{'Measured V_p/V_s ≥ √2','Pop-B: n = 236 (target-informed)'},gray,false);
bx(.512,.78,.218,.11,{'Fold-local preprocessing','training rows only'},green,false);
bx(.512,.60,.218,.11,{'Gaussian kernel | MLFFNN','DFFNN | CNN1D'},green,false);
bx(.512,.42,.218,.11,{'Inner OOF meta-features','scaled Ridge stacker'},green,false);
bx(.512,.24,.218,.11,{'Nested depth-blocked CV','5 outer × 4 inner folds','R^2 = 0.6386 | RMSE = 0.0585 km/s'},green,true);
bx(.762,.78,.225,.11,{'Frozen primary stacker','refit on Well-A only'},red,false);
bx(.762,.60,.225,.11,{'Pop-A external evaluation','R^2 = −2.7331'},red,true);
bx(.762,.42,.225,.11,{'DT shift diagnostic','z = +7.85 | KS = 1.000'},red,false);
bx(.762,.24,.225,.11,{'Post-hoc comparators','I-CNN | Hybrid I-CNN | Direct Ridge'},gray,false);
for x=[.121 .371 .621 .874], for y=[.755 .575], arr(x,y); end, end
arr(.371,.395);
arr(.621,.395);
text(ax,.5,.105,'44/44 predefined clean-session checks PASS for the frozen primary pipeline.', ...
    'HorizontalAlignment','center','FontName','Arial','FontSize',6.8,'FontWeight','bold','Color',[.05 .42 .08]);
text(ax,.5,.060,'Post-processing diagnostics (measured-log consistency, error decomposition, and V_p/V_s bands) were computed after frozen-pipeline verification and are outside the 44 checks.', ...
    'HorizontalAlignment','center','FontName','Arial','FontSize',6.15,'Color',[.3 .3 .3]);
exportgraphics(f,fullfile(pkg,'JAG_Fig2_validation_workflow.png'),'Resolution',300);
exportgraphics(f,fullfile(out,'Fig2.tif'),'Resolution',300);
close(f);
    function hdr(x,s,c), text(ax,x,.965,s,'HorizontalAlignment','center','FontWeight','bold','FontName','Arial','FontSize',8,'Color',c); end
    function bx(x,y,w,h,lines,fc,bold)
        rectangle(ax,'Position',[x y w h],'FaceColor',fc,'EdgeColor',edge,'LineWidth',.55,'Curvature',.03);
        fw='normal'; if bold,fw='bold';end
        text(ax,x+w/2,y+h/2,strjoin(lines,newline),'HorizontalAlignment','center','VerticalAlignment','middle','FontName','Arial','FontSize',6.8,'FontWeight',fw,'Interpreter','tex');
    end
    function arr(x,y), quiver(ax,x,y,0,-.035,0,'Color',[.35 .35 .35],'LineWidth',.7,'MaxHeadSize',2); end
end

function make_fig6(root,pkg,out)
p1=fullfile(root,'runs','ped_extension_run_PED_corrected_20260910_071523_20260910_114659', ...
    '05_external_models','PED_EXTERNAL_ALL_MODELS_ROW_PREDICTIONS.csv');
p2=fullfile(root,'runs','run_AJSE_ICNN_corrected_20261001_111157','03_external', ...
    'AJSE_EXTERNAL_ROW_PREDICTIONS.csv');
A=readtable(p1); B=readtable(p2);
A=A(logical(A.IS_POPA),:); B=B(logical(B.IS_POPA),:);
[tf,loc]=ismember(A.ROW_ID,B.ROW_ID); assert(all(tf)&&height(A)==329);
y=A.VS_MEASURED;
P=[A.PRED_PNN,A.PRED_MLFFNN,A.PRED_DFFNN,A.PRED_CNN1D,A.PRED_RIDGE_STACKER, ...
   B.PRED_I_CNN(loc),B.PRED_HYBRID_I_CNN(loc),A.PRED_DIRECT_RIDGE];
names={'Gaussian kernel','MLFFNN','DFFNN','CNN1D','Ridge stacker','I-CNN*','Hybrid I-CNN*','Direct Ridge*'};
r2=zeros(1,8); rmse=r2; bias=r2;
for k=1:8
    r2(k)=1-sum((y-P(:,k)).^2)/sum((y-mean(y)).^2);
    rmse(k)=sqrt(mean((P(:,k)-y).^2)); bias(k)=mean(P(:,k)-y);
end
expected=[-3.3387 -3.5039 -214.6054 -142.1181 -2.7331 -0.7273 -0.0881 0.6831];
assert(max(abs(r2-expected))<6e-4,'Unexpected saved-prediction metrics');
cols=lines(8); cols(1,:)=[.55 .55 .55]; cols(5,:)=[.80 .30 .05]; cols(7,:)=[.38 .62 .42]; cols(8,:)=[.15 .42 .65];
f=figure('Visible','off','Color','w','Units','centimeters','Position',[0 0 18 13.5]);
t=tiledlayout(f,2,2,'TileSpacing','compact','Padding','compact');
ax=nexttile(t,1); hold(ax,'on'); sel=[5 7 8]; mk={'o','^','s'};
for q=1:3, scatter(ax,y,P(:,sel(q)),8,cols(sel(q),:),'filled','Marker',mk{q},'MarkerFaceAlpha',.38,'DisplayName',names{sel(q)}); end
ps=P(:,sel); lo=min([y;ps(:)]); hi=max([y;ps(:)]); pad=.04*(hi-lo); plot(ax,[lo-pad hi+pad],[lo-pad hi+pad],'k-','HandleVisibility','off');
axis(ax,'square'); xlim(ax,[lo-pad hi+pad]); ylim(ax,[lo-pad hi+pad]); grid(ax,'on'); box(ax,'off');
xlabel(ax,'Measured V_s (km/s)'); ylabel(ax,'Predicted V_s (km/s)'); title(ax,'(a) Representative Pop-A predictions','FontWeight','bold');
legend(ax,'Location','southoutside','Orientation','horizontal','Box','off','FontSize',5.8);

ax=nexttile(t,2); b=barh(ax,r2,'FaceColor','flat'); b.CData=cols; yline(ax,0); grid(ax,'on'); box(ax,'off');
set(ax,'YTick',1:8,'YTickLabel',names,'YDir','reverse','FontSize',6.7); xlabel(ax,'R^2'); title(ax,'(b) Full-scale external performance','FontWeight','bold'); xlim(ax,[-225 5]);
for k=1:8
    if r2(k)<-10, tx=r2(k)+3; ha='left';
    elseif r2(k)<0, tx=r2(k)-1; ha='right';
    else, tx=r2(k)+.25; ha='left'; end
    text(ax,tx,k,sprintf('%.3f',r2(k)),'HorizontalAlignment',ha,'FontSize',5.8);
end

ax=nexttile(t,3); keep=[1 2 5 6 7 8]; b=barh(ax,r2(keep),'FaceColor','flat'); b.CData=cols(keep,:); xline(ax,0); grid(ax,'on'); box(ax,'off');
set(ax,'YTick',1:numel(keep),'YTickLabel',names(keep),'YDir','reverse','FontSize',6.7); xlabel(ax,'R^2'); title(ax,'(c) Near-zero detail','FontWeight','bold'); xlim(ax,[-4 1]);
for q=1:numel(keep)
    k=keep(q);
    if r2(k)<0
        labelColor='w';
        labelX=r2(k)+.10;
        if k==7
            labelColor=[.1 .1 .1];
            labelX=r2(k)+.14;
        end
        text(ax,labelX,q,sprintf('%.3f',r2(k)),'HorizontalAlignment','left', ...
            'Color',labelColor,'FontWeight','bold','FontSize',5.6);
    else
        text(ax,r2(k)-.05,q,sprintf('%.3f',r2(k)),'HorizontalAlignment','right', ...
            'Color',[.1 .1 .1],'FontWeight','bold','FontSize',5.6);
    end
end

ax=nexttile(t,4); hold(ax,'on'); yr=[min(y) max(y)]; patch(ax,[.5 8.5 8.5 .5],[yr(1) yr(1) yr(2) yr(2)],[.88 .88 .88],'EdgeColor','none','DisplayName','Measured range');
for k=1:8, plot(ax,[k k],[min(P(:,k)) max(P(:,k))],'-','Color',cols(k,:),'LineWidth',2); plot(ax,k,median(P(:,k)),'ko','MarkerFaceColor',cols(k,:),'MarkerSize',4); end
set(ax,'XTick',1:8,'XTickLabel',names,'XTickLabelRotation',35,'FontSize',6.2); xlim(ax,[.5 8.5]); grid(ax,'on'); box(ax,'off'); ylabel(ax,'Predicted V_s range (km/s)'); title(ax,'(d) Prediction-range diagnostic','FontWeight','bold');
exportgraphics(f,fullfile(pkg,'JAG_Fig6_all_model_external_comparison.png'),'Resolution',300);
exportgraphics(f,fullfile(out,'Fig6.tif'),'Resolution',300);
close(f);
T=table(string(names)',r2',rmse',bias','VariableNames',{'MODEL','R2','RMSE','BIAS'});
writetable(T,fullfile(pkg,'JAG_Fig6_external_model_metrics.csv'));
end

function out=tern(cond,a,b)
if cond,out=a;else,out=b;end
end
