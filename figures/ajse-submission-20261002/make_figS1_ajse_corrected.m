function make_figS1_ajse_corrected()
% Regenerate AJSE Fig. S1 from the frozen population counts.
% Terminology follows the manuscript: exact-duplicate exclusion and a
% target-informed measured-Vp/Vs screen, not depth-only leakage or QC.

out_dir = fullfile(fileparts(mfilename('fullpath')), 'Figures_AJSE');
if ~isfolder(out_dir); mkdir(out_dir); end

n_total = 492;
n_exact = 163;
n_popA = 329;
n_screen = 93;
n_popB = 236;
assert(n_total - n_exact == n_popA);
assert(n_popA - n_screen == n_popB);

blue = [0.231 0.447 0.635];
green1 = [0.259 0.580 0.298];
green2 = [0.133 0.545 0.133];
red = [0.62 0.16 0.16];
dark = [0.12 0.12 0.12];
gray = [0.42 0.42 0.42];

fig = figure('Units','centimeters','Position',[0 0 18.2 7.7], ...
    'Visible','off','Color','white');
tl = tiledlayout(fig,1,2,'TileSpacing','compact','Padding','compact');

% Panel (a)
ax1 = nexttile(tl,1); hold(ax1,'on');
x = [1.0 2.4 3.8];
counts = [n_total n_popA n_popB];
colors = {blue,green1,green2};
for i = 1:3
    bar(ax1,x(i),counts(i),0.53,'FaceColor',colors{i}, ...
        'EdgeColor',[0.20 0.20 0.20],'LineWidth',0.35);
end

% Count labels sit clearly above bars.
count_labels = {sprintf('n = %d',n_total), ...
    sprintf('Pop-A\nn = %d',n_popA), sprintf('Pop-B\nn = %d',n_popB)};
offsets = [14 13 13];
for i = 1:3
    text(ax1,x(i),counts(i)+offsets(i),count_labels{i}, ...
        'HorizontalAlignment','center','VerticalAlignment','bottom', ...
        'FontSize',7.7,'FontWeight','bold','Color',colors{i}, ...
        'Interpreter','none','Clipping','off');
end

% Removal annotations sit above the resulting bars, clear of plotted data.
text(ax1,2.40,420,sprintf('−%d\nexact duplicates',n_exact), ...
    'HorizontalAlignment','center','VerticalAlignment','middle', ...
    'FontSize',7.0,'FontWeight','bold','Color',red,'Interpreter','none');
text(ax1,3.80,345,sprintf('−%d\nmeasured Vp/Vs ≥ √2\nscreen',n_screen), ...
    'HorizontalAlignment','center','VerticalAlignment','middle', ...
    'FontSize',5.9,'FontWeight','bold','Color',red,'Interpreter','none');

plot(ax1,[1.27 2.13],[n_total n_total],'--','Color',[0.48 0.48 0.48],'LineWidth',0.7);
plot(ax1,[2.67 3.53],[n_popA n_popA],'--','Color',[0.48 0.48 0.48],'LineWidth',0.7);

set(ax1,'XTick',x,'XTickLabel',{'Well-B total','Pop-A','Pop-B'}, ...
    'FontName','Arial','FontSize',7.8,'YLim',[0 550],'XLim',[0.35 4.45], ...
    'TickLabelInterpreter','none','LineWidth',0.7,'Box','off');
ylabel(ax1,'Sample count','FontName','Arial','FontSize',8.5);
title(ax1,'(a) Sample retention','FontName','Arial','FontSize',9, ...
    'FontWeight','bold','Color',dark);
grid(ax1,'on'); ax1.GridAlpha = 0.20; ax1.Layer = 'top';

% Panel (b)
ax2 = nexttile(tl,2); axis(ax2,'off'); hold(ax2,'on');
col_x = [0.02 0.65 0.79];
col_w = [0.62 0.13 0.19];
row_h = 0.165;
y_hdr = 0.82;
hdr_bg = [0.25 0.25 0.30];
row_bgs = {[0.86 0.91 1.00],[0.94 0.97 0.88],[0.85 0.97 0.85]};
headers = {'Stage','n','Retained'};
for ci = 1:3
    rectangle(ax2,'Position',[col_x(ci) y_hdr col_w(ci) row_h], ...
        'FaceColor',hdr_bg,'EdgeColor','white','LineWidth',0.9);
    text(ax2,col_x(ci)+col_w(ci)/2,y_hdr+row_h/2,headers{ci}, ...
        'HorizontalAlignment','center','VerticalAlignment','middle', ...
        'FontName','Arial','FontSize',7.8,'FontWeight','bold', ...
        'Color','white','Interpreter','none');
end

rows = {
    'Well-B total', 492, '100.0%';
    'Pop-A: exact-copy excluded', 329, '66.9%';
    'Pop-B*: measured Vp/Vs ≥ √2 screen', 236, '48.0%'};
for ri = 1:3
    y = y_hdr - ri*row_h;
    rectangle(ax2,'Position',[0.02 y 0.96 row_h], ...
        'FaceColor',row_bgs{ri},'EdgeColor',[0.72 0.72 0.72],'LineWidth',0.35);
    vals = {rows{ri,1},num2str(rows{ri,2}),rows{ri,3}};
    for ci = 1:3
        fs = 7.2;
        if ri == 3 && ci == 1; fs = 6.5; end
        text(ax2,col_x(ci)+col_w(ci)/2,y+row_h/2,vals{ci}, ...
            'HorizontalAlignment','center','VerticalAlignment','middle', ...
            'FontName','Arial','FontSize',fs,'Color',dark,'Interpreter','none');
    end
end

note = sprintf(['163 exact duplicate records excluded\n' ...
    '(depth, GR, DT, NPHI, RHOB, Vs).\n' ...
    '93 additional rows excluded by measured Vp/Vs ≥ √2 screen.\n' ...
    '* Pop-B is a target-informed diagnostic subset.']);
text(ax2,0.50,0.29,note,'HorizontalAlignment','center', ...
    'VerticalAlignment','top','FontName','Arial','FontSize',6.1, ...
    'Color',gray,'Interpreter','none');
title(ax2,'(b) Canonical mask definition','FontName','Arial','FontSize',9, ...
    'FontWeight','bold','Color',dark);
xlim(ax2,[0 1]); ylim(ax2,[0.18 1.08]);

drawnow;
base = fullfile(out_dir,'FigS1_AJSE');
exportgraphics(fig,[base '.png'],'Resolution',600,'BackgroundColor','white');
exportgraphics(fig,[base '.pdf'],'ContentType','vector','BackgroundColor','white');
savefig(fig,[base '.fig']);
exportgraphics(fig,fullfile(out_dir,'FigS1.tif'),'Resolution',600,'BackgroundColor','white');
close(fig);

fprintf('AJSE Fig. S1 regenerated: %s\n', out_dir);
end
