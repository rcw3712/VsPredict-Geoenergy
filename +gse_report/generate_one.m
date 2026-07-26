function export_info = generate_one(fig_id, bundle)
% GSE_REPORT.GENERATE_ONE  Dispatch to individual figure maker.
switch upper(strtrim(fig_id))
    case 'FIG01'; export_info = gse_report.make_fig01(bundle);
    case 'FIG02'; export_info = gse_report.make_fig02(bundle);
    case 'FIG03'; export_info = gse_report.make_fig03(bundle);
    case 'FIG04'; export_info = gse_report.make_fig04(bundle);
    case 'FIG05'; export_info = gse_report.make_fig05(bundle);
    case 'FIG06'; export_info = gse_report.make_fig06(bundle);
    case 'FIG07'; export_info = gse_report.make_fig07(bundle);
    case 'FIG08'; export_info = gse_report.make_fig08(bundle);
    otherwise
        error('gse_report:generate_one','Unknown figure ID: %s', fig_id);
end
end
