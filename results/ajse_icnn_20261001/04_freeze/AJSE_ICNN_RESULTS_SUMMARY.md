# AJSE I-CNN comparator results

- Run: `run_AJSE_ICNN_corrected_20261001_111157`
- Corrected reference: `run_PED_corrected_20260910_071523`
- Provenance: `HISTORICAL_ARCHITECTURE_POST_HOC_REEVALUATION`
- Well-B used for fitting/tuning: **No**
- Cross-segment windows retained: **0**

## Interpretation rule

I-CNN and Hybrid I-CNN are additional post-hoc comparators. They do not replace the frozen primary Ridge stacker and must not be described as prospectively pre-specified.

## Nested outer OOF

- Ridge_stacker: R2 0.6386; RMSE 0.0585; MAE 0.0456; bias -0.0043; n=392.
- I_CNN: R2 0.3076; RMSE 0.0810; MAE 0.0647; bias +0.0296; n=392.
- Hybrid_I_CNN: R2 0.3781; RMSE 0.0768; MAE 0.0637; bias +0.0268; n=392.

## Contiguous holdout

- Ridge_stacker: R2 0.3591; RMSE 0.1147; MAE 0.0872; bias +0.0610; n=100.
- I_CNN: R2 -0.3029; RMSE 0.1635; MAE 0.1240; bias +0.0483; n=100.
- Hybrid_I_CNN: R2 0.3841; RMSE 0.1124; MAE 0.0836; bias -0.0251; n=100.

## Full-Well-A external deployment


### POP_A_PRIMARY_NON_DUPLICATE

- Ridge_stacker: R2 -2.7331; RMSE 0.4181; MAE 0.3794; bias +0.3768; n=329.
- I_CNN: R2 -0.7273; RMSE 0.2844; MAE 0.2411; bias +0.2309; n=329.
- Hybrid_I_CNN: R2 -0.0881; RMSE 0.2257; MAE 0.1997; bias -0.1931; n=329.
- Direct_Ridge: R2 0.6831; RMSE 0.1218; MAE 0.0904; bias -0.0112; n=329.

### POP_B_TARGET_INFORMED_DIAGNOSTIC

- Ridge_stacker: R2 -5.4721; RMSE 0.4698; MAE 0.4416; bias +0.4416; n=236.
- I_CNN: R2 -2.1166; RMSE 0.3260; MAE 0.2917; bias +0.2913; n=236.
- Hybrid_I_CNN: R2 -0.0632; RMSE 0.1904; MAE 0.1671; bias -0.1580; n=236.
- Direct_Ridge: R2 0.6504; RMSE 0.1092; MAE 0.0730; bias +0.0374; n=236.

Total elapsed time: 28.1 minutes.
