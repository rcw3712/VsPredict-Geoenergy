# ABLATION_REPORT.md
| Config | Features | Model | CV R² | CV RMSE |
|---|---|---|---:|---:|
| A1_FULL | GR,DT,NPHI,RHOB | ridge_stacker | 0.5972±0.1819 | 0.0510±0.0092 |
| A2_S2 | RHOB,DT | ridge_stacker | 0.6051±0.1907 | 0.0500±0.0086 |
| A3_WITHOUT_GR | DT,NPHI,RHOB | ridge_stacker | 0.6283±0.1397 | 0.0494±0.0076 |
| A4_WITHOUT_DT | GR,NPHI,RHOB | ridge_stacker | 0.3466±0.7052 | 0.0621±0.0340 |
| A5_WITHOUT_NPHI | GR,DT,RHOB | ridge_stacker | 0.5405±0.2513 | 0.0537±0.0109 |
| A6_WITHOUT_RHOB | GR,DT,NPHI | ridge_stacker | 0.4498±0.3142 | 0.0584±0.0135 |
| B1_PNN | GR,DT,NPHI,RHOB | pnn | 0.6263±0.1776 | 0.0488±0.0116 |
| B2_RIDGE | GR,DT,NPHI,RHOB | ridge_stacker | 0.5972±0.1819 | 0.0510±0.0092 |
| B3_ICNN | GR,DT,NPHI,RHOB | icnn | 0.4921±0.2347 | 0.0581±0.0195 |
| B4_HYBRID | GR,DT,NPHI,RHOB | hybrid_icnn | 0.3670±0.3327 | 0.0626±0.0237 |
