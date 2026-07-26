# VsPredict-Geoenergy

Reproducibility code for:

> Wibowo, R.C., Mahli, R.A.K., Kumalasari, I.N., Kurniawan, A., Husni, Y.M., Mulyanto, B.S., & Sarkowi, M. **Cross-Well Shear-Wave Velocity Prediction from Conventional Well Logs under Severe Covariate Shift: Reproducible Leakage-Free Validation and Geomechanical Consequences.** Submitted to *Geoenergy Science and Engineering* (Elsevier).

This repository contains the MATLAB pipeline used to develop, validate, and evaluate machine-learning models for predicting shear-wave velocity (Vs) from conventional well logs (GR, DT, NPHI, RHOB), with a leakage-free, depth-blocked, Well-A-only model-development protocol and a genuinely blind, non-overlapping cross-well evaluation on Well-B.

## What this repository contains

| Path | Contents |
|---|---|
| `+core/` | Core pipeline: run initialization, data loading, preprocessing, feature selection, hyperparameter tuning, ablation study, I-CNN audit, run-freezing/validation |
| `+models/` | Model implementations: PNN, MLFFNN, DFFNN, CNN1D (base learners); Ridge stacker, I-CNN, Hybrid I-CNN (meta-learners); Direct Ridge (post-hoc sensitivity model); LSBoost, SVR |
| `+gse_report/` | Figure generation, manifest/caption generation, and QC checks used to produce the manuscript's figures and supplementary material |
| `config/config_geoenergy_v4.m` | Master configuration (structural settings only — column mappings, feature lists, physical-QC ranges; **no hard-coded scientific results**) |
| `tests/` | Pipeline integrity tests (no hard-coded metrics, no duplicate active functions, canonical-run identity, path uniqueness) |
| `main_numerical_pipeline.m`, `run_pipeline.m`, `run_gate15.m` | Top-level entry points |
| `results/reference_outputs/` | Non-sensitive summary tables and reports from the canonical frozen run (`run_20260723_170341`), matching the numbers reported in the manuscript — provided for independent verification of a re-run |

## What is **not** included

- **Well-log data** (`data/Well-A.xlsx`, `data/Well-B.xlsx`): proprietary, provided under confidentiality agreement, and cannot be redistributed (see the manuscript's Data Availability statement). To run this pipeline, supply your own well-log data in the same column format (see `config/config_geoenergy_v4.m`, `cfg.data.col_map`).
- **Trained model binaries** (`.mat` files): excluded to avoid distributing anything derived from the proprietary dataset.
- **Full run archive**: only the canonical run's published summary tables/reports are included (`results/reference_outputs/`), not the complete intermediate run folder structure.

## Reproducing the analysis

1. Requires MATLAB (developed and frozen under **R2024a**, 24.1.0.2537033 — see `results/reference_outputs/RNG_AND_ENVIRONMENT_REPORT.md` and `CONFIG_SNAPSHOT.txt` for the exact environment used for the canonical run).
2. Place your own well-log files at `data/Well-A.xlsx` and `data/Well-B.xlsx` (column names per `config/config_geoenergy_v4.m`).
3. From the repository root, run:
   ```matlab
   run_pipeline
   ```
4. Cross-run reproducibility can be checked with:
   ```matlab
   run_gate15
   ```
   which reproduces the 23-check comparison reported in the manuscript (Table 6 / Gate-15).
5. Figures and captions matching the manuscript are generated via the `+gse_report` package (see `+gse_report/generate_all.m`).

## Key results (for verification against your own re-run)

All values below are from the canonical frozen run (`run_20260723_170341`) and are reported in full in the manuscript; see `results/reference_outputs/` for the underlying tables.

| Quantity | Value |
|---|---|
| Nested CV R² (Ridge stacker, Well-A) | 0.6418 ± 0.1486 |
| Internal holdout R² (Well-A) | 0.2668 |
| Blind R², Pop-A (n=329) | −3.9607 |
| Blind R², Pop-B (n=236) | −7.3973 |
| DT domain-shift z-score | +7.86 (100% out-of-distribution) |
| Gate-15 cross-run reproducibility | 23 / 23 checks passed |
| Direct Ridge (post-hoc) blind R², Pop-A / Pop-B | 0.6804 / 0.6599 |

## Repository scope note

This pipeline evolved through several internal versions during development; some intermediate/legacy files referenced in historical development notes are not part of the active pipeline and are not included here. The files listed above under "What this repository contains" reflect the code paths actually used to produce the frozen canonical run and the manuscript's reported results.

## Citation

If you use this code, please cite the manuscript above. A `CITATION.cff` file is included for automated citation tools.

## License

See `LICENSE`. Code is released under the MIT License; this does **not** extend to any well-log data, which remains proprietary and is not distributed here.

## Contact

Rahmat Catur Wibowo — Geological Engineering Department, Universitas Lampung — rahmat.caturwibowo@eng.unila.ac.id
