function cfg = config_geoenergy_v4()
% CONFIG_GEOENERGY_V4  Master configuration for VsPredict_Geoenergy_v4.
%
%  Compliant with CLAUDE_PROMPT_V4_GEOENERGY_PIPELINE.md
%  Rule 1.6: No hard-coded scientific results in code.
%  Rule 1.4: Every run gets a unique RUN_ID.
%  All values in this config are STRUCTURAL (architecture, paths, policy),
%  not scientific results. Results come from the frozen run bundle.

cfg = struct();

%% STUDY IDENTITY
cfg.study.name         = 'VsPredict_Geoenergy_v4';
cfg.study.version      = '4.0';
cfg.study.target       = 'Geoenergy Science and Engineering (Elsevier Q1)';
cfg.study.anon_stmt    = ['Field, reservoir, operator, and geographic identifiers '...
    'have been anonymized. This does not alter measured values or methods.'];

%% DATA
cfg.data.well_A_file   = 'data/Well-A.xlsx';
cfg.data.well_B_file   = 'data/Well-B.xlsx';
cfg.data.sheet         = 1;
cfg.data.col_map       = {'DEPTH (M)','DEPTH';'GR (API)','GR';'VSH (%)','VSH';
                           'DT (US/F)','DT';'DTS (US/F)','DTS';
                           'NPHI (%)','NPHI';'RHOB (G/CM3)','RHOB'};
cfg.data.features      = {'GR','DT','NPHI','RHOB'};  % S1_FULL
cfg.data.target_col    = 'VS';   % derived: 304.8/DTS [km/s]
cfg.data.exclude_cols  = {'VSH'};

%% PHYSICAL RANGES (for validity audit — not used for imputation decisions)
cfg.sanity.GR          = [0,    150];   % GAPI
cfg.sanity.DT          = [50,   160];   % us/ft
cfg.sanity.NPHI        = [0,    60];    % %
cfg.sanity.RHOB        = [1.85, 2.75];  % g/cc
cfg.sanity.VS          = [0.80, 3.50];  % km/s
cfg.sanity.VP          = [2.00, 5.50];  % km/s
cfg.sanity.vpvs_min    = sqrt(2);       % physical minimum
cfg.sanity.vpvs_max    = 2.50;
cfg.sanity.nu_min      = 0.0;
cfg.sanity.nu_max      = 0.5;

%% DEPTH BOUNDARIES
% These are structural: must match the actual data once loaded.
% They are stored here as policy, overridden during audit phase.
cfg.depth.wellB_seg0_max  = 2724.9872;  % last depth of Seg0
cfg.depth.wellB_seg1_min  = 2750.1396;  % first depth of Seg1
cfg.depth.nominal_step    = 0.1524;     % m (0.5 ft)
cfg.depth.gap_threshold   = 0.762;      % m = 5 nominal steps

%% PARTITIONING
cfg.split.test_frac    = 0.20;  % Well-A internal holdout fraction
cfg.split.kfold        = 5;     % inner depth-blocked folds

%% SEEDS
cfg.seeds.all          = [7, 42, 123];
cfg.seeds.canonical    = 42;

% Per-model seed offsets (Rule §12)
cfg.seeds.offset_pnn          = 101;
cfg.seeds.offset_mlffnn       = 201;
cfg.seeds.offset_dffnn        = 301;
cfg.seeds.offset_cnn1d        = 401;
cfg.seeds.offset_ridge        = 501;
cfg.seeds.offset_icnn         = 601;
cfg.seeds.offset_hybrid_icnn  = 701;
cfg.seeds.offset_svr          = 801;
cfg.seeds.offset_lsboost      = 901;
cfg.seeds.offset_fold_mult    = 10000;  % fold_id * offset_fold_mult added to model seed
cfg.seeds.offset_refit        = 90000;

%% PREPROCESSING POLICY
cfg.preproc.iqr_k             = 1.5;
cfg.preproc.zscore_thresh     = 3.0;     % for imputation eligibility check only
cfg.preproc.knn_k             = 5;
cfg.preproc.savgol_order      = 2;
cfg.preproc.savgol_window     = 11;
cfg.preproc.normalize         = 'zscore';
% OOD policy: OOD values are FLAGGED, not imputed (Rule 7.3)
cfg.preproc.ood_z2_flag_only  = true;
cfg.preproc.ood_z3_flag_only  = true;
% Target clean: DTS/VS NEVER modified (Rule 7.2)
cfg.preproc.target_clean      = true;

%% FEATURE SELECTION
cfg.fs.S1_full                = {'GR','DT','NPHI','RHOB'};
cfg.fs.mrmr_topk              = 3;
cfg.fs.lasso_alpha            = 1.0;
cfg.fs.combine_method         = 'intersection';  % fallback: union
cfg.fs.nested                 = true;  % nested inside each fold (Rule 9.2)

%% BASE LEARNER DEFAULTS (hyperparams tuned during Phase 8)
cfg.base.window               = 16;

%% STACKING META-LEARNER CONFIGURATION
cfg.stack.base_order          = {'pnn','mlffnn','dffnn','cnn1d'};  % fixed order
cfg.stack.meta_candidates     = {'ridge_stacker','icnn','hybrid_icnn'};
cfg.stack.tie_thresh          = 0.005;
cfg.stack.tie_break_order     = {'ridge_stacker','icnn','hybrid_icnn'};  % simpler first

%% EVALUATION POPULATIONS (Rule §8)
cfg.eval.pop_A_name    = 'PRIMARY_ALL_OBSERVED';   % Seg0 non-overlap, observed VS
cfg.eval.pop_B_name    = 'PHYSICAL_QC_SUBSET';     % + measured Vp/Vs >= sqrt(2)

%% CLIPPING (exactly once, after inverse scaling, in physical units)
cfg.clip.vs_min        = 0.80;  % km/s
cfg.clip.vs_max        = 3.50;  % km/s
cfg.clip.apply_once    = true;

%% EXECUTION ENVIRONMENT (Rule §4.2)
cfg.compute.execution_environment = 'cpu';
cfg.compute.use_parallel          = false;
cfg.compute.allow_gpu             = false;
cfg.training.shuffle              = 'never';

%% OUTPUT (structural — scientific values come from run bundle)
cfg.output.runs_dir     = 'runs';
cfg.output.font         = 'Times New Roman';
cfg.output.fontsize     = 10;
cfg.output.fontsize_sm  = 8;
cfg.output.lw           = 1.0;
cfg.output.lw_thin      = 0.75;
cfg.output.width_in     = 174/25.4;   % double column
cfg.output.max_h_in     = 234/25.4;
cfg.output.dpi_line_art    = 1000;
cfg.output.dpi_combination = 500;
cfg.output.dpi_halftone    = 300;
cfg.output.dpi_preview     = 150;

% Colours (colorblind-accessible via IBM colour-blind palette)
cfg.output.color_A         = [0.122, 0.467, 0.706];   % blue
cfg.output.color_B         = [0.839, 0.153, 0.157];   % red
cfg.output.color_deploy    = [0.173, 0.627, 0.173];   % green
cfg.output.color_emp       = [0.800, 0.600, 0.200];   % orange
cfg.output.color_dup       = [0.750, 0.750, 0.750];   % grey

fprintf('  [CFG v4] Configuration loaded\n');
end
