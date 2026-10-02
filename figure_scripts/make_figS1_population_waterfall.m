function result = make_figS1_population_waterfall(canon_run_folder, out_dir)
% MAKE_FIGS1_POPULATION_WATERFALL  Fig S1: retention bars 492→329→236.
%   Redesigned: retention counts only; removal annotations as text between bars.
%   Summary table: 3 columns (Stage, n, Retained %).

if nargin < 1; canon_run_folder = fullfile(nrr_project_root(),'runs','run_20260903_155408'); end
if nargin < 2; out_dir = fullfile(nrr_project_root(),'figures_final'); end

nrr_figure_style();
D = nrr_load_canonical(canon_run_folder);
nrr_assert_canonical(D);

n_tot  = D.nWellB;   % 492
n_popA = D.nPopA;    % 329
n_popB = D.nPopB;    % 236
n_ex1  = D.nShared;  % 163
n_ex2  = n_popA - n_popB;  % 93
assert(n_ex2 == 93);
assert(n_tot - n_ex1 == n_popA);
assert(n_popA - n_ex2 == n_popB);

% Verify counts against the canonical row-role ledger.
role_path=fullfile(canon_run_folder,'01_data_audit','DATA_ROLE_ROW_IDS.csv');
assert(isfile(role_path),'FIGS1: role ledger not found');
Tr=readtable(role_path,'TextType','string');
n_dup=nnz(Tr.ROLE=="Well-B duplicate");
n_popA_only=nnz(Tr.ROLE=="Pop-A primary blind" | Tr.ROLE=="Pop-A primary external");
n_popB_ledger=nnz(Tr.ROLE=="Pop-B diagnostic QC" | Tr.ROLE=="Pop-B target-informed diagnostic");
assert(n_dup==n_ex1 && n_popA_only+n_popB_ledger==n_popA && ...
    n_popB_ledger==n_popB,'FIGS1: role-ledger counts mismatch');

c = nrr_colors();
fig = figure('Units','centimeters','Position',[0 0 17.4 7.2],'Visible','off','Color','white');
tl  = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

% ── Panel (a): Retention bars 492 → 329 → 236 ────────────────────────────────
ax1 = nexttile(tl,1);
hold(ax1,'on');

% Three retention bars (not removal bars)
x_pos   = [1, 2, 3];
counts  = [n_tot, n_popA, n_popB];
clrs    = {c.wellA, [0.259 0.580 0.298], [0.133 0.545 0.133]};
for i = 1:3
    bar(ax1, x_pos(i), counts(i), 0.55, 'FaceColor', clrs{i}, 'EdgeColor','none');
end

% Removal annotations above the retained-population bars. Equal depth alone is
% not treated as leakage; exclusion requires exact agreement in all audited
% variables.
text(ax1, 2, n_popA+82, sprintf('−%d exact duplicates',n_ex1),...
    'HorizontalAlignment','center','VerticalAlignment','middle',...
    'FontSize',8,'Color',[0.6 0.15 0.15],'FontWeight','bold','Interpreter','none');
text(ax1, 3, n_popB+58, sprintf('−%d measured Vp/Vs >= sqrt(2) screen',n_ex2),...
    'HorizontalAlignment','center','VerticalAlignment','middle',...
    'FontSize',7,'Color',[0.6 0.15 0.15],'FontWeight','bold','Interpreter','none');

% Connector dashed lines
for i = 1:2
    plot(ax1,[i+0.28,i+0.72],[counts(i),counts(i)],'--','Color',[0.5 0.5 0.5],'LineWidth',0.7);
end

% Value labels
pct = counts/n_tot*100;
lbl = {sprintf('n = %d\n(100%%)',n_tot), sprintf('Pop-A\nn = %d\n(%.1f%%)',n_popA,pct(2)), ...
       sprintf('Pop-B\nn = %d\n(%.1f%%)',n_popB,pct(3))};
for i=1:3
    text(ax1,i,counts(i)+8,lbl{i},'HorizontalAlignment','center','FontSize',8,...
        'FontWeight','bold','Color',clrs{i},'Interpreter','none');
end

set(ax1,'XTick',1:3,'XTickLabel',{'Well-B total','Pop-A','Pop-B'},...
    'FontSize',8,'YLim',[0 n_tot+55],'XLim',[0.4 3.6],'TickLabelInterpreter','none');
ylabel(ax1,'Sample count','FontSize',9);
title(ax1,'(a) Sample retention','FontSize',9,'FontWeight','bold','Interpreter','none');
grid(ax1,'on');

% ── Panel (b): Simplified 3-column table ────────────────────────────────────
ax2 = nexttile(tl,2);
axis(ax2,'off'); hold(ax2,'on');

% 3 columns: Stage | n | Retained
col_x = [0.01, 0.58, 0.72]; col_w = [0.56, 0.13, 0.27];
row_h = 0.165; y_hdr = 0.84;
hdr_bg = [0.25 0.25 0.30]; fg_hdr = [1 1 1];
row_bgs = {[0.86 0.91 1.0],[0.94 0.97 0.88],[0.85 0.97 0.85]};
hdrs = {'Stage','n','Retained'};

% Header
for ci=1:3
    rectangle(ax2,'Position',[col_x(ci) y_hdr col_w(ci) row_h],...
        'FaceColor',hdr_bg,'EdgeColor','none');
    text(ax2,col_x(ci)+col_w(ci)/2,y_hdr+row_h/2,hdrs{ci},...
        'HorizontalAlignment','center','VerticalAlignment','middle',...
        'FontSize',8.5,'FontWeight','bold','Color',fg_hdr,'Interpreter','none');
end

% Rows
rows = {
    'Well-B total',         492,   '100.0%';
    'Pop-A: exact-copy excluded', 329, '66.9%';
    'Pop-B*: measured Vp/Vs >= sqrt(2) screen', 236,   '48.0%';
};
for ri=1:3
    y_row = y_hdr - ri*row_h - 0.005;
    rectangle(ax2,'Position',[0.01 y_row 0.98 row_h],...
        'FaceColor',row_bgs{ri},'EdgeColor',[0.75 0.75 0.75],'LineWidth',0.3);
    vals = {rows{ri,1}, num2str(rows{ri,2}), rows{ri,3}};
    for ci=1:3
        text(ax2,col_x(ci)+col_w(ci)/2,y_row+row_h/2,vals{ci},...
            'HorizontalAlignment','center','VerticalAlignment','middle',...
            'FontSize',8,'Interpreter','none');
    end
end

% Note below table
text(ax2,0.50,0.29,...
    sprintf(['163 exact duplicate records excluded (depth, GR, DT, NPHI, RHOB, Vs).\n' ...
    '93 additional rows were excluded by the measured Vp/Vs >= sqrt(2) screen.\n' ...
    '* Pop-B is a target-informed diagnostic subset.']),...
    'HorizontalAlignment','center','VerticalAlignment','top','FontSize',6.5,'Color',[0.4 0.4 0.4],'Interpreter','none');

title(ax2,'(b) Canonical mask definition','FontSize',9,'FontWeight','bold','Interpreter','none');
xlim(ax2,[0 1]); ylim(ax2,[0.2 1.1]);

nrr_assert_canonical(D);
drawnow;
nrr_export_figure(fig, out_dir, 'FIGS1_population_waterfall');
result=struct('status','PASS','name','FIGS1_population_waterfall', ...
    'png_path',fullfile(out_dir,'FIGS1_population_waterfall.png'), ...
    'pdf_path',fullfile(out_dir,'FIGS1_population_waterfall.pdf'), ...
    'counts',[n_tot n_popA n_popB],'excluded',[n_ex1 n_ex2], ...
    'population_status','Pop-B target-informed diagnostic');
close(fig);
end
