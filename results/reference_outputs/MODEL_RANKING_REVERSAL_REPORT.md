# MODEL_RANKING_REVERSAL_REPORT.md
Run: run_20260723_170341

## Pop-A Rankings (n=329)
| Rank | Model | Pop-A R² | Pop-A RMSE |
|---:|---|---:|---:|
| 1 | direct_ridge | 0.6804 | 0.1223 |
| 2 | hybrid_icnn | -0.4048 | 0.2565 |
| 3 | icnn | -2.4276 | 0.4007 |
| 4 | pnn | -3.3387 | 0.4508 |
| 5 | ridge_stacker | -3.9607 | 0.4820 |
| 6 | GC_sand | -4.2275 | 0.4948 |
| 7 | training_mean | -4.7968 | 0.5211 |
| 8 | Castagna_mudrock | -5.0952 | 0.5343 |
| 9 | GC_limestone | -5.1575 | 0.5370 |
| 10 | GC_shale | -7.6262 | 0.6356 |
| 11 | cnn1d | -60.5715 | 1.6982 |
| 12 | mlffnn | -60.5885 | 1.6984 |
| 13 | dffnn | -60.8163 | 1.7015 |

## Pop-B Rankings (n=236)
| Rank | Model | Pop-B R² | Pop-B RMSE |
|---:|---|---:|---:|
| 1 | direct_ridge | 0.6599 | 0.1077 |
| 2 | hybrid_icnn | -0.3882 | 0.2176 |
| 3 | GC_sand | -4.7581 | 0.4432 |
| 4 | icnn | -4.9511 | 0.4505 |
| 5 | GC_limestone | -5.8020 | 0.4817 |
| 6 | Castagna_mudrock | -5.8491 | 0.4833 |
| 7 | pnn | -6.4685 | 0.5047 |
| 8 | ridge_stacker | -7.3973 | 0.5352 |
| 9 | GC_shale | -8.9714 | 0.5832 |
| 10 | training_mean | -9.1858 | 0.5894 |
| 11 | cnn1d | -91.7418 | 1.7785 |
| 12 | mlffnn | -91.7923 | 1.7790 |
| 13 | dffnn | -92.2096 | 1.7830 |

## Ranking Reversal Conclusion
Internal CV ranking did not predict external blind ranking.
Under severe covariate shift, simpler linear models generalized better.
