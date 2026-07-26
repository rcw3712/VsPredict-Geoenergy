# STACKING_VALUE_ADDED_REPORT.md
Run: run_20260723_170341 | Seed: 42

## Summary
Ridge stacker (RMSE=0.0482) outperforms PNN (RMSE=0.0488) on CV

## All Models (CV RMSE, common basis)
| Model | CV R² | CV RMSE | Holdout R² |
|---|---:|---:|---:|
| pnn | 0.6263 | 0.0488 | NaN |
| mlffnn | -5.6395 | 0.2139 | NaN |
| dffnn | -9.4396 | 0.2467 | NaN |
| cnn1d | -8.6916 | 0.2330 | NaN |
| direct_ridge | 0.6265 | 0.0493 | NaN |
| ridge_stacker | 0.6418 | 0.0482 | 0.2668 |
| icnn | 0.1572 | 0.0756 | 0.1187 |
| hybrid_icnn | 0.2112 | 0.0711 | -0.2319 |

Best by CV RMSE: **ridge_stacker** (0.0482)

## Note
The original model selection (Level 1) chose Ridge stacker as best meta-learner based on Well-A internal holdout R². This Level-2 analysis uses blocked-CV RMSE on the same k=5 folds, providing a common evaluation basis across all model types. Well-B was not used for any selection decision.
