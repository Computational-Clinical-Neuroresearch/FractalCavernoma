# FractalCavernoma Project Structure

GPU-accelerated neuroimaging pipeline for radiomics and fractal analysis of cavernous malformations.

## Directory Structure

```
FractalCavernoma/
├── bin/                           # Executable scripts
│   └── setup_cav_data.sh         # Data organization script (33 CAV subjects)
│
├── data/                          # All data files
│   ├── metadata/                  # Study metadata
│   │   └── 25612080/             # Cambridge BIDS dataset metadata
│   │       ├── Metadata_Release_Anon.csv
│   │       └── Metadata_Controls_Release.csv
│   ├── raw_data/                  # Original BIDS dataset (not in git)
│   ├── patients/                  # Full dataset: 33 subjects × 2 sequences = 66 scans
│   └── test_patients/             # Test subset: 2 subjects × 2 sequences = 4 scans
│
├── scripts/                       # Processing scripts
│   ├── mri_preprocess_part1.sh   # N4 bias field correction
│   ├── mri_preprocess_part2.sh   # Registration, skull stripping, normalization
│   ├── run_pipeline_parallel.sh  # Parallel processing with GPU load balancing
│   ├── zscore_normalise.py       # Z-score normalization (lesion-excluded)
│   ├── extract_radiomics.py      # PyRadiomics feature extraction (1,409 features)
│   ├── extract_fractal.py        # 3D fractal dimension & lacunarity (16 features)
│   └── start_vnc.sh              # VNC server for ITK-SNAP
│
├── results/                       # Analysis outputs
│   ├── fractal_features.csv      # Fractal metrics (16 features × 4 subjects)
│   └── radiomics_features.csv    # Radiomics features (1,409 features × 4 subjects)
│
├── logs/                          # Processing logs
│   ├── test_patients_part1.log   # Part 1 job log
│   └── test_patients_part2.log   # Part 2 job log
│
├── docs/                          # Documentation
│   ├── README_PIPELINE.md        # Pipeline usage guide
│   ├── GPU_SETUP_SUMMARY.md      # GPU configuration
│   ├── VNC_SETUP_GUIDE.md        # ITK-SNAP via VNC
│   └── GETTING_STARTED.md        # Quick start guide
│
├── Dockerfile                     # Docker environment definition
├── docker-compose.yml            # Docker orchestration with GPU
└── README.md                      # Main project README

```

## Data Organization

### Input Structure (per subject)
```
patients/sub-{ID}_{SEQUENCE}/
├── Input_NIfTI/
│   ├── sub-{ID}_{SEQUENCE}.nii.gz           # Original scan
│   └── sub-{ID}_{SEQUENCE}_lesion_mask.nii.gz  # Manual lesion mask
├── Output_Part1/
│   └── sub-{ID}_{SEQUENCE}_Step1_BFC.nii.gz    # Bias field corrected
├── Output_Part2/
│   ├── sub-{ID}_{SEQUENCE}_Step2_MNI.nii.gz         # MNI registered
│   ├── sub-{ID}_{SEQUENCE}_Step3_SkullStrip.nii.gz  # Skull stripped
│   ├── sub-{ID}_{SEQUENCE}_Step4_ZScore.nii.gz      # Z-score normalized
│   ├── sub-{ID}_{SEQUENCE}_lesion_mask_MNI.nii.gz   # Lesion mask in MNI
│   └── sub-{ID}_{SEQUENCE}_normalisation_mask.nii.gz
└── Lesion_Mask/
    └── sub-{ID}_{SEQUENCE}_lesion_mask.nii.gz      # Original lesion mask
```

## Pipeline Overview

### Part 1: Bias Field Correction (CPU)
- **Input**: Raw T1w/FLAIR NIfTI
- **Method**: ANTs N4BiasFieldCorrection
- **Output**: Bias-corrected image
- **Runtime**: ~30s per scan

### Part 2: Registration & Normalization (GPU)
- **Steps**:
  1. **Registration**: ANTs to MNI152 (rigid + affine, lesion-masked)
  2. **Skull Stripping**: HD-BET (GPU-accelerated)
  3. **Z-score Normalization**: Lesion-excluded statistics
- **Runtime**: ~2-3 min per scan (GPU)

### Feature Extraction

#### Radiomics (PyRadiomics)
- **Features**: 1,409 per lesion
  - Shape: 14 (volume, sphericity, compactness, etc.)
  - First-order: 252 (mean, kurtosis, entropy across 14 image types)
  - Texture: 1,143 (GLCM, GLRLM, GLSZM, GLDM, NGTDM)
- **Image types**: 14 (Original + 8 wavelet + 5 filters)
- **Runtime**: ~2-3 min per scan

#### Fractal Analysis (imea)
- **Features**: 16 per lesion
  - Fractal Dimension: 8 (axial/coronal/sagittal × mean/median + 3D)
  - Lacunarity: 8 (axial/coronal/sagittal × mean/median + 3D)
- **Methods**:
  - FD: Box-counting algorithm
  - Lacunarity: Gliding-box algorithm
- **Runtime**: ~1-2 min per scan

## Key Technologies

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| Container | Docker + NVIDIA | 12.2.0-runtime | GPU acceleration |
| Preprocessing | ANTs | 2.5.0 | N4, registration |
| Brain Extraction | HD-BET | 2.0.1 | GPU skull stripping |
| Radiomics | PyRadiomics | 3.0.1 | Feature extraction |
| Fractal Analysis | imea | latest | FD & lacunarity |
| Deep Learning | PyTorch | 2.0.1+cu118 | HD-BET backend |
| Image I/O | nibabel, SimpleITK | 5.2.0, 2.3.1 | NIfTI handling |

## GPU Configuration

- **GPUs Used**: Device IDs 0, 1
- **Parallel Processing**:
  - Part 1: 4 subjects in parallel (CPU-bound)
  - Part 2: 2 subjects in parallel (1 per GPU)
- **Memory**: ~8GB per HD-BET process

## Dataset Summary

### Full Dataset
- **Subjects**: 33 with cavernous malformations
- **Sequences**: T1w + FLAIR (66 scans total)
- **Source**: Cambridge BIDS dataset
- **Selection**: Filtered from metadata for CAV pathology

### Test Dataset
- **Subjects**: 2 (sub-6, sub-18)
- **Scans**: 4 (2 subjects × 2 sequences)
- **Purpose**: Pipeline validation

## Usage

### Run Full Pipeline on Test Data
```bash
# Inside container
cd /workspace/scripts
./run_pipeline_parallel.sh test_patients both
```

### Extract Radiomics Features
```bash
python3 /workspace/scripts/extract_radiomics.py test_patients radiomics_features.csv
```

### Extract Fractal Metrics
```bash
python3 /workspace/scripts/extract_fractal.py test_patients fractal_features.csv
```

### Process Full Dataset
```bash
./run_pipeline_parallel.sh patients both
python3 /workspace/scripts/extract_radiomics.py patients radiomics_all.csv
python3 /workspace/scripts/extract_fractal.py patients fractal_all.csv
```

## Output Files

### Feature CSVs
- **radiomics_features.csv**: 1,409 columns + 3 metadata (subject_id, subject_num, sequence)
- **fractal_features.csv**: 16 columns + 3 metadata

### Preprocessed Images
- **Step4_ZScore.nii.gz**: Final preprocessed images (MNI space, skull-stripped, normalized)
- **lesion_mask_MNI.nii.gz**: Lesion masks in MNI space

## Citation

**Pipeline adapted from:**
- Fractal analysis: [Fractal-Dimension-and-Lacunarity-in-Gliomas](https://github.com/nibr-lab/Fractal-Dimension-and-Lacunarity-in-Gliomas)
- HD-BET: Isensee et al., arXiv:1901.11341
- PyRadiomics: van Griethuysen et al., Cancer Research 2017

## Next Steps

1. **Run full dataset** (66 scans)
2. **Feature selection** (correlation analysis, variance thresholding)
3. **Statistical analysis** (compare T1w vs FLAIR, clinical correlations)
4. **Machine learning** (classification, survival prediction)
5. **Boundary segmentation** (for true fractal analysis)
