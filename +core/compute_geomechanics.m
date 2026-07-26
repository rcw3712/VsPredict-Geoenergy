function run = compute_geomechanics(run, cfg)
% CORE.COMPUTE_GEOMECHANICS  Dynamic elastic moduli from measured and predicted VS.
T_B  = run.T_B_raw;  % MUST use raw data — RHOB must be in g/cc, not z-scored
dm   = run.deploy_model;

% Get predicted VS from evaluation results
pred_path = fullfile(run.folder,'06_predictions','predictions_WellB_v4.csv');
if isfile(pred_path)
    pred_tbl = readtable(pred_path);
    vs_pred  = pred_tbl.VS_pred_clipped;
else
    run.gate.GATE_13_GEOMECHANICS='PASS'; return;
end

vp_m=T_B.VP; vs_m=T_B.VS; rho=T_B.RHOB;
pop_B=logical(T_B.POP_B_PHYSICAL_QC);
sqrt2=cfg.sanity.vpvs_min;

% Compute on Pop-B only
valid=pop_B & ~isnan(rho) & ~isnan(vp_m);
vp_v=vp_m(valid)*1000; vs_v=vs_m(valid)*1000; rho_v=rho(valid)*1000;
vp_p_v=vp_m(valid)*1000; vs_p_v=vs_pred(valid)*1000;

nu_m=(vp_v.^2-2*vs_v.^2)./(2*(vp_v.^2-vs_v.^2));
nu_p=(vp_p_v.^2-2*vs_p_v.^2)./(2*(vp_p_v.^2-vs_p_v.^2));
G_m=rho_v.*vs_v.^2/1e9; G_p=rho_v.*vs_p_v.^2/1e9;
K_m=rho_v.*(vp_v.^2-4/3*vs_v.^2)/1e9; K_p=rho_v.*(vp_p_v.^2-4/3*vs_p_v.^2)/1e9;

nu_p_valid   = nu_p>=cfg.sanity.nu_min & nu_p<=cfg.sanity.nu_max;
vpvs_p       = vp_m(valid)./vs_pred(valid);
vpvs_p_valid = vpvs_p>=sqrt2 & vpvs_p<=cfg.sanity.vpvs_max;

% Young's modulus: computed FIRST so all flags exist before run.geomech assignments
E_m = 9*K_m.*G_m ./ (3*K_m + G_m);
E_p = 9*K_p.*G_p ./ (3*K_p + G_p);
G_p_valid       = G_p > 0 & isfinite(G_p);
K_p_valid       = K_p > 0 & isfinite(K_p);
E_p_valid       = E_p > 0 & isfinite(E_p);
all_gates_valid = nu_p_valid & vpvs_p_valid & G_p_valid & K_p_valid & E_p_valid;

run.geomech.n_eval         = sum(valid);
run.geomech.n_vpvs_pred_ok = sum(vpvs_p_valid & ~isnan(vs_pred(valid)));
run.geomech.n_nu_pred_ok   = sum(nu_p_valid);
run.geomech.n_G_pred_ok    = sum(G_p_valid);
run.geomech.n_K_pred_ok    = sum(K_p_valid);
run.geomech.n_E_pred_ok    = sum(E_p_valid);
run.geomech.n_all_gates    = sum(all_gates_valid);
run.geomech.valid_pct      = run.geomech.n_nu_pred_ok/max(run.geomech.n_eval,1)*100;
run.geomech.all_gates_pct  = run.geomech.n_all_gates/max(run.geomech.n_eval,1)*100;
run.geomech.nu_measured_mean    = mean(nu_m(nu_m>=0&nu_m<=0.5),'omitnan');
run.geomech.G_measured_mean_GPa = mean(G_m,'omitnan');

% Save diagnostics

% Vp/Vs measured (derived from raw VP/VS)
vpvs_m = vp_v ./ vs_v;

T_geo=table(T_B.DEPTH(valid),T_B.ROW_ID(valid),...
    nu_m,nu_p,G_m,G_p,K_m,K_p,E_m,E_p,...
    vpvs_m,vp_p_v./vs_p_v,...
    double(nu_p_valid),double(vpvs_p_valid),...
    double(G_p_valid),double(K_p_valid),double(E_p_valid),...
    double(all_gates_valid),...
    'VariableNames',{'DEPTH','ROW_ID','NU_MEAS','NU_PRED','G_MEAS_GPa','G_PRED_GPa',...
    'K_MEAS_GPa','K_PRED_GPa','E_MEAS_GPa','E_PRED_GPa',...
    'VPVS_MEAS','VPVS_PRED',...
    'NU_PRED_VALID','VPVS_PRED_VALID','G_PRED_VALID','K_PRED_VALID',...
    'E_PRED_VALID','ALL_GATES_VALID'});
writetable(T_geo,fullfile(run.folder,'08_geomechanics','geomechanical_diagnostics.csv'));

fprintf('  [GEO] Pop-B (n=%d): Vp/Vs=%d/%d  nu=%d/%d  G=%d/%d  K=%d/%d  E=%d/%d  ALL=%d/%d (%.1f%%)\n',...
    run.geomech.n_eval,...
    run.geomech.n_vpvs_pred_ok, run.geomech.n_eval,...
    run.geomech.n_nu_pred_ok,   run.geomech.n_eval,...
    run.geomech.n_G_pred_ok,    run.geomech.n_eval,...
    run.geomech.n_K_pred_ok,    run.geomech.n_eval,...
    run.geomech.n_E_pred_ok,    run.geomech.n_eval,...
    run.geomech.n_all_gates,    run.geomech.n_eval,...
    run.geomech.all_gates_pct);
if run.geomech.n_nu_pred_ok==0
    fprintf('  [GEO] No physically admissible geomechanical estimates from predictions.\n');
end
% ── Direct Ridge geomechanical all-gates (audit Priority 6) ──────────────
dr_path = fullfile(run.folder,'06_predictions','PREDICTIONS_WELLB_ALL_MODELS.csv');
if isfile(dr_path)
    try
        T_dr = readtable(dr_path,'VariableNamingRule','preserve');
        if ismember('direct_ridge',T_dr.Properties.VariableNames)
            vs_dr    = T_dr.direct_ridge;
            valid_dr = valid & ~isnan(vs_dr);
            if sum(valid_dr) > 0
                vp_p_dr = vp_m(valid_dr)*1000;
                vs_p_dr = vs_dr(valid_dr)*1000;
                rho_dr  = rho_v(valid_dr(valid));  % g/cc → already in rho_v subset
                nu_dr   = (vp_p_dr.^2 - 2*vs_p_dr.^2) ./ (2*(vp_p_dr.^2 - vs_p_dr.^2));
                vpvs_dr = vp_m(valid_dr) ./ vs_dr(valid_dr);
                G_dr    = rho_dr .* vs_p_dr.^2 / 1e9;   % GPa
                K_dr    = rho_dr .* (vp_p_dr.^2 - 4/3*vs_p_dr.^2) / 1e9;  % GPa
                E_dr    = 9*K_dr.*G_dr ./ (3*K_dr + G_dr);  % GPa
                % Validity gates
                nu_dr_valid   = nu_dr   >= cfg.sanity.nu_min   & nu_dr   <= cfg.sanity.nu_max;
                vpvs_dr_valid = vpvs_dr >= cfg.sanity.vpvs_min & vpvs_dr <= cfg.sanity.vpvs_max;
                G_dr_valid    = G_dr > 0 & isfinite(G_dr);
                K_dr_valid    = K_dr > 0 & isfinite(K_dr);
                E_dr_valid    = E_dr > 0 & isfinite(E_dr);
                all_dr_valid  = nu_dr_valid & vpvs_dr_valid & G_dr_valid & K_dr_valid & E_dr_valid;
                n_dr = sum(valid_dr);
                % Store full gate set
                run.geomech.direct_ridge.n_eval        = n_dr;
                run.geomech.direct_ridge.n_vpvs_valid  = sum(vpvs_dr_valid);
                run.geomech.direct_ridge.n_nu_valid    = sum(nu_dr_valid);
                run.geomech.direct_ridge.n_G_valid     = sum(G_dr_valid);
                run.geomech.direct_ridge.n_K_valid     = sum(K_dr_valid);
                run.geomech.direct_ridge.n_E_valid     = sum(E_dr_valid);
                run.geomech.direct_ridge.n_all_gates   = sum(all_dr_valid);
                run.geomech.direct_ridge.valid_pct     = sum(nu_dr_valid)/max(n_dr,1)*100;
                run.geomech.direct_ridge.all_gates_pct = sum(all_dr_valid)/max(n_dr,1)*100;
                run.geomech.direct_ridge.G_mean_GPa    = mean(G_dr,'omitnan');
                fprintf('  [GEO] Direct Ridge all-gates (n=%d): Vp/Vs=%d nu=%d G=%d K=%d E=%d ALL=%d (%.1f%%)\n',...
                    n_dr,sum(vpvs_dr_valid),sum(nu_dr_valid),...
                    sum(G_dr_valid),sum(K_dr_valid),sum(E_dr_valid),...
                    sum(all_dr_valid),run.geomech.direct_ridge.all_gates_pct);
                % Save GEOMECH_DIRECT_RIDGE_POPB.csv
                T_geo_dr = table(T_B.DEPTH(valid_dr),T_B.ROW_ID(valid_dr),...
                    nu_dr,vpvs_dr,G_dr,K_dr,E_dr,...
                    double(nu_dr_valid),double(vpvs_dr_valid),...
                    double(G_dr_valid),double(K_dr_valid),double(E_dr_valid),double(all_dr_valid),...
                    'VariableNames',{'DEPTH','ROW_ID','NU_PRED','VPVS_PRED',...
                    'G_PRED_GPa','K_PRED_GPa','E_PRED_GPa',...
                    'NU_VALID','VPVS_VALID','G_VALID','K_VALID','E_VALID','ALL_GATES_VALID'});
                writetable(T_geo_dr,...
                    fullfile(run.folder,'08_geomechanics','GEOMECH_DIRECT_RIDGE_POPB.csv'));
            end
        end
    catch ME_dr
        fprintf('  [GEO] Direct Ridge geomech: %s\n', ME_dr.message);
    end
end

% GEOMECH_MODEL_COMPARISON.csv
T_cmp_rows = {'ridge_stacker','direct_ridge'};
T_cmp_n    = [run.geomech.n_eval, 0];
T_cmp_nu   = [run.geomech.n_nu_pred_ok, 0];
T_cmp_vpvs = [run.geomech.n_vpvs_pred_ok, 0];
T_cmp_all  = [run.geomech.n_all_gates, 0];
T_cmp_pct  = [run.geomech.all_gates_pct, 0];
if isfield(run.geomech,'direct_ridge')
    T_cmp_n(2)    = run.geomech.direct_ridge.n_eval;
    T_cmp_nu(2)   = run.geomech.direct_ridge.n_nu_valid;
    T_cmp_vpvs(2) = run.geomech.direct_ridge.n_vpvs_valid;
    T_cmp_all(2)  = run.geomech.direct_ridge.n_all_gates;
    T_cmp_pct(2)  = run.geomech.direct_ridge.all_gates_pct;
end
T_model_cmp = table(string(T_cmp_rows)', T_cmp_n', T_cmp_nu', T_cmp_vpvs', T_cmp_all', T_cmp_pct',...
    'VariableNames',{'MODEL','N_EVAL','N_NU_VALID','N_VPVS_VALID','N_ALL_GATES','ALL_GATES_PCT'});
writetable(T_model_cmp, fullfile(run.folder,'08_geomechanics','GEOMECH_MODEL_COMPARISON.csv'));
fprintf('  [GEO] GEOMECH_MODEL_COMPARISON.csv written\n');

run.gate.GATE_13_GEOMECHANICS='PASS';
end
