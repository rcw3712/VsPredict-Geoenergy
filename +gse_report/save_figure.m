function ei = save_figure(fig_handle, basename, artwork_type, bundle)
% GSE_REPORT.SAVE_FIGURE  Export to TIFF (submission) + PDF (vector) + PNG (preview).
%   artwork_type: 'line_art'(1000dpi) | 'combination'(500dpi) | 'halftone'(300dpi)
%   Closes figure ONLY after all exports complete.

ei = struct('tiff','','pdf','','png','','status','FAIL');
cfg = bundle.cfg_fig;

% Resolve parent figure
if isa(fig_handle,'matlab.ui.Figure') || isgraphics(fig_handle,'figure')
    fig = fig_handle;
else
    fig = ancestor(fig_handle,'figure');
end
if isempty(fig) || ~isgraphics(fig)
    ei.error = sprintf('save_figure(%s): invalid handle', basename);
    fprintf('  [WARN] %s\n', ei.error); return;
end

switch lower(strtrim(artwork_type))
    case 'line_art';    dpi = cfg.dpi_line_art;
    case 'combination'; dpi = cfg.dpi_combination;
    case 'halftone';    dpi = cfg.dpi_halftone;
    otherwise;          dpi = cfg.dpi_combination;
end
ei.dpi = dpi;

main_dir = fullfile(bundle.out,'figures_main');
prev_dir = fullfile(bundle.out,'figures_preview');
tiff_path = fullfile(main_dir, [basename '.TIF']);
pdf_path  = fullfile(main_dir, [basename '.pdf']);
png_path  = fullfile(prev_dir, [basename '_preview.png']);

% TIFF — primary submission format
try
    if exist('exportgraphics','file')
        exportgraphics(fig, tiff_path, 'Resolution',dpi,'BackgroundColor','white');
    else
        print(fig, tiff_path, '-dtiff', sprintf('-r%d',dpi));
    end
    ei.tiff = tiff_path;
catch ME_t
    fprintf('  [WARN] TIFF %s: %s\n', basename, ME_t.message);
end

% PDF — vector
try
    if exist('exportgraphics','file')
        exportgraphics(fig, pdf_path,'ContentType','vector','BackgroundColor','white');
    else
        print(fig, pdf_path, '-dpdf', '-bestfit');
    end
    ei.pdf = pdf_path;
catch ME_p
    fprintf('  [WARN] PDF %s: %s\n', basename, ME_p.message);
end

% PNG preview
try
    print(fig, png_path, '-dpng', '-r150');
    ei.png = png_path;
catch ME_n
    fprintf('  [WARN] PNG %s: %s\n', basename, ME_n.message);
end

drawnow; try; close(fig); catch; end

if ~isempty(ei.tiff)
    ei.status = 'PASS';
    fprintf('  [FIG] %s.TIF (%d dpi)\n', basename, dpi);
else
    ei.status = 'FAIL';
end
end
