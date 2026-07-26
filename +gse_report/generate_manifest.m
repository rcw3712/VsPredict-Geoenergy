function generate_manifest(bundle, fig_status)
run=bundle.run; out=bundle.out;
fig_ids=keys(fig_status);
rows={};
for fi=1:numel(fig_ids)
    fid=fig_ids{fi};
    fname=fig_id_to_fname(fid);
    tif_path=fullfile(out,'figures_main',[fname '.TIF']);
    src_csv=[fname '_source_data.csv'];
    rows{fi}={fid,fname,run.id,string(run.cfg.seeds.canonical),...
        string(run.eval_popB.n),fig_status(fid),...
        string(isfile(tif_path)),string(isfile(fullfile(out,'figures_source_data',src_csv)))};
end
T=cell2table(vertcat(rows{:}),...
    'VariableNames',{'Figure_ID','Filename','Run_ID','Seed','n_PopB','Status','TIFF_ok','SrcData_ok'});
writetable(T,fullfile(out,'FIGURE_MANIFEST.csv'));
fprintf('  [QC] FIGURE_MANIFEST.csv\n');
end

function f=fig_id_to_fname(fid)
m=struct('FIG01','FIG01_study_design_and_validation','FIG02','FIG02_well_logs_and_qc',...
    'FIG03','FIG03_domain_shift','FIG04','FIG04_model_development_and_selection',...
    'FIG05','FIG05_multiseed_and_consistency','FIG06','FIG06_blind_well_evaluation',...
    'FIG07','FIG07_cross_domain_diagnostics','FIG08','FIG08_geomechanical_consequences');
safe=matlab.lang.makeValidName(fid); if isfield(m,safe); f=m.(safe); else; f=fid; end
end
