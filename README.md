# VsPredict external-well shear-wave velocity archive

This repository is the project-history and reproducibility archive for the VsPredict cross-well shear-wave velocity study. The repository name `VsPredict-NRR` is historical: it is an umbrella archive for immutable predecessor snapshots and the current analysis prepared for *Arabian Journal for Science and Engineering* (AJSE), Petroleum Engineering.

Earlier tagged and branched snapshots remain available for provenance. They are not authoritative for the current AJSE manuscript.

## Current AJSE analysis

Manuscript working title:

> **External-Well Validation of Machine-Learning Shear-Wave Velocity Prediction from Conventional Well Logs under Severe Sonic-Log Shift: A Two-Well Case Study**

This is a two-well calibration-to-external-well study. It evaluates one transfer event and does not claim population-wide geological generalization. Well-B had been examined in predecessor project analyses; consequently, `frozen primary` and `post hoc` denote the analysis hierarchy and are not claims of prospective preregistration.

| Item | Authoritative AJSE value |
|---|---:|
| Corrected reference run | `run_PED_corrected_20260910_071523` |
| Corrected extension manifest | `ped_extension_run_PED_corrected_20260910_071523_20260910_114659` |
| AJSE I-CNN comparator run | `run_AJSE_ICNN_corrected_20261001_111157` |
| Well-A development / same-well holdout | 392 / 100 |
| Exact duplicate records excluded | 163 |
| Primary external population, Pop-A | 329 |
| Target-informed diagnostic population, Pop-B | 236 |
| Nested depth-blocked CV | 5 outer × 4 inner folds |
| Pooled outer-OOF R² / RMSE | 0.6386 / 0.0585 km/s |
| Mean outer-fold R² | 0.5152 ± 0.1675 |
| Corrected same-well holdout R² | 0.3591 |
| Frozen primary Ridge stacker Pop-A R² | −2.7331 |
| Post-hoc I-CNN / Hybrid I-CNN Pop-A R² | −0.7273 / −0.0881 |
| Post-hoc Direct Ridge Pop-A R² | 0.6831 |
| Frozen primary Ridge stacker Pop-B R² | −5.4721 |
| DT shift z(B\|A) / KS | +7.85 / 1.000 |
| Ridge / Direct Ridge Pop-B ALL-OK | 0/236 / 236/236 |
| Clean-session cross-run checks | 44/44 PASS |

All four frozen base learners had negative Pop-A R². Historical I-CNN and Hybrid I-CNN architectures were re-evaluated after the frozen primary analysis and remain post-hoc comparators. Direct Ridge was introduced only after the primary transfer failure and is a post-hoc exploratory benchmark. None of these comparators redefines the frozen primary model.

## Corrected provenance

The earlier same-well holdout value R² = −3.0622 is a legacy result invalidated by raw meta-feature scaling. It is retained only as software provenance and must not be used as a scientific result. The corrected fixed-hyperparameter holdout value is R² = 0.3591.

The corrected pipeline propagates physical depth-segment identifiers to CNN fitting and rejects windows crossing disconnected training segments. The frozen PNN spread candidate set is exactly `0.1, 0.2, 0.5, 1.0, 2.0`; the older string `0.1:0.1:2.0` was an erroneous provenance transcription and is superseded.

## Repository layout

```text
+nrr_data/                     shared loading, roles, folds, preprocessing
+nrr_models/                   base learners, segment-aware CNN, stacker
+nrr_eval/                     nested CV, external evaluation, diagnostics
+nrr_report/                   report generation
ped_extension/                 corrected targeted extension and audit gates
ajse_extension/                I-CNN and Hybrid I-CNN comparator pipeline
results/ped_corrected_20260910/
  canonical/                   non-sensitive corrected aggregate outputs
  extension/                   non-sensitive corrected extension outputs
results/ajse_icnn_20261001/    non-sensitive AJSE comparator aggregates
figures/ajse-submission-20261002/
                               final AJSE TIFF figures and editable Fig. S1
tests/                         inherited integrity tests
run_ped_corrected_pipeline.m   corrected reference-pipeline entry point
selftest_ped_codex_patch_v3.m  fail-closed patch self-test
```

Legacy NRR- and PED-named MATLAB packages, file paths, and run identifiers are retained where renaming would break reproducibility and manifest hashes. Their names do not define the current journal target.

## Reproduction sequence

Requirements: MATLAB R2024a plus Statistics and Machine Learning Toolbox and Deep Learning Toolbox. Proprietary well logs are not distributed.

Place authorized inputs at:

```text
data/Well-A.xlsx
data/Well-B.xlsx
```

Run the patch self-test and corrected reference pipeline:

```matlab
clear classes
clear functions
rehash toolboxcache
selftest_ped_codex_patch_v3
result = run_ped_corrected_pipeline;
```

Create a second independent clean-session run and compare the two run IDs:

```matlab
result = run_reproducibility_check('run_ID_1', 'run_ID_2', pwd);
```

Run the corrected targeted extension only after the reference run and cross-run verification pass:

```matlab
cd ped_extension
run_ped_targeted_extension
```

Run the AJSE historical-architecture comparators from the project root:

```matlab
addpath('ajse_extension')
selftest_ajse_icnn_comparator
result = run_ajse_icnn_comparator;
```

The committed aggregate outputs correspond to the three run identifiers above. Row-level predictions, well logs, trained model binaries, checkpoints, and re-identification-sensitive artifacts are intentionally excluded.

## Figures

The current submission figures are under [`figures/ajse-submission-20261002`](figures/ajse-submission-20261002). `FIGURE_MANIFEST_SHA256.csv` records hashes and source-run provenance.

- Figures 1 and 7 depend on audited logs, masks, and distribution-shift statistics.
- Figures 2–6 and 8 use the corrected reference and AJSE comparator results.
- Supplementary Fig. S1 uses `exact duplicate` terminology and a target-informed measured Vp/Vs screen; its MATLAB `.fig`, vector PDF, PNG, TIFF, and source script are included.
- Supplementary Fig. S2 uses corrected multi-seed outputs.

## Archive and citation status

- GitHub: this repository is the project-history umbrella archive.
- Zenodo concept DOI: [`10.5281/zenodo.21614275`](https://doi.org/10.5281/zenodo.21614275).
- The existing PED-era Zenodo version is a historical snapshot and does not yet constitute a versioned AJSE release.
- Before final publication, create a dedicated versioned GitHub/Zenodo release from the AJSE submission commit and cite the version-specific DOI in the accepted article.

## Data policy

The well logs are proprietary and are not included. The public package contains source code, non-sensitive aggregate tables, configuration/provenance summaries, figure files, and cryptographic manifests. Independent numerical execution requires authorized access to the original inputs.

## License

Source code is released under the MIT License. The license does not apply to proprietary well-log data.
