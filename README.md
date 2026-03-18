# FractalCavernoma: GPU-Accelerated Neuroimaging Pipeline

GPU-accelerated preprocessing, radiomics, and fractal analysis pipeline for cavernous malformation MRI scans.

---

## Quick Start

```bash
# 1. Build Docker image (~30-60 min)
docker compose build

# 2. Start container
docker compose up -d
docker exec -it fractal-cavernoma-pipeline bash

# 3. Run full pipeline on test data (4 scans)
cd /workspace/scripts
./run_pipeline_parallel.sh test_patients both

# 4. Extract features
python3 extract_radiomics.py test_patients radiomics.csv    # 1,409 features
python3 extract_fractal.py test_patients fractal.csv        # 16 features
```

---

## Table of Contents

- [Dataset](#dataset)
- [Directory Structure](#directory-structure)
- [Pipeline Overview](#pipeline-overview)
- [GPU Configuration](#gpu-configuration)
- [Feature Extraction](#feature-extraction)
- [Usage Examples](#usage-examples)
- [Manual Segmentation](#manual-segmentation-optional)
- [Troubleshooting](#troubleshooting)

---

## Dataset

**Source**: Cambridge BIDS dataset (OpenNeuro)
- **Total subjects**: 33 with cavernous malformations
- **Sequences**: T1w + FLAIR (30 paired, 3 T1w only)
- **Total scans**: 66
- **Test subset**: 2 subjects × 2 sequences = 4 scans

**Data organization**:
```bash
# Inside container
cd /workspace
./bin/setup_cav_data.sh  # Creates patients/ and test_patients/
```

---

## Directory Structure

```
FractalCavernoma/
├── bin/
│   └── setup_cav_data.sh         # Data organization script
│
├── data/
│   ├── metadata/                  # Study metadata (Cambridge dataset)
│   ├── raw_data/                  # Original BIDS dataset (not in git)
│   ├── patients/                  # Full dataset (66 scans)
│   └── test_patients/             # Test subset (4 scans)
│
├── scripts/
│   ├── mri_preprocess_part1.sh   # N4 bias field correction
│   ├── mri_preprocess_part2.sh   # Registration, skull-strip, normalize
│   ├── run_pipeline_parallel.sh  # GPU-accelerated batch processing
│   ├── zscore_normalise.py       # Z-score normalization
│   ├── extract_radiomics.py      # PyRadiomics feature extraction
│   ├── extract_fractal.py        # 3D fractal dimension & lacunarity
│   └── start_vnc.sh              # VNC server for ITK-SNAP
│
├── results/                       # Feature CSVs
│   ├── radiomics_features.csv
│   └── fractal_features.csv
│
├── logs/                          # Pipeline logs
│
├── Dockerfile                     # Container definition
├── docker-compose.yml            # GPU orchestration
├── README.md                      # This file
└── PROJECT_STRUCTURE.md          # Detailed structure documentation
```

**Subject directory structure**:
```
patients/sub-{ID}_{SEQUENCE}/
├── Input_NIfTI/
│   ├── sub-{ID}_{SEQUENCE}.nii.gz               # Original scan
│   └── sub-{ID}_{SEQUENCE}_lesion_mask.nii.gz   # Manual mask (you create this)
├── Output_Part1/
│   └── sub-{ID}_{SEQUENCE}_Step1_BFC.nii.gz     # Bias corrected
└── Output_Part2/
    ├── sub-{ID}_{SEQUENCE}_Step2_MNI.nii.gz     # MNI registered
    ├── sub-{ID}_{SEQUENCE}_Step3_SkullStrip.nii.gz  # Skull stripped
    ├── sub-{ID}_{SEQUENCE}_Step4_ZScore.nii.gz  # Final (for radiomics)
    └── sub-{ID}_{SEQUENCE}_lesion_mask_MNI.nii.gz   # Mask in MNI space
```

---

## Pipeline Overview

### Part 1: Bias Field Correction (CPU)
- **Method**: ANTs N4BiasFieldCorrection
- **Runtime**: ~30s per scan
- **Parallelization**: 4 subjects at once

**Steps**:
1. Load raw T1w/FLAIR NIfTI
2. Apply N4 bias correction (3 iterations, shrink factor 3)
3. Save to `Output_Part1/`

### Part 2: Registration & Normalization (GPU)
- **Runtime**: ~2-3 min per scan
- **Parallelization**: 2 subjects at once (1 per GPU)

**Steps**:
1. **Registration to MNI152**: ANTs rigid + affine (lesion-masked to exclude from cost function)
2. **Skull Stripping**: HD-BET with GPU acceleration
3. **Z-score Normalization**: Mean=0, SD=1 (lesion voxels excluded from statistics)

### Feature Extraction

#### Radiomics (PyRadiomics)
- **Features**: 1,409 per lesion
  - Shape: 14 (volume, sphericity, surface area, etc.)
  - First-order: 252 (mean, kurtosis, entropy × 14 image types)
  - Texture: 1,143 (GLCM, GLRLM, GLSZM, GLDM, NGTDM)
- **Image types**: Original + 8 wavelet + 5 filters (14 total)
- **Runtime**: ~2-3 min per scan

#### Fractal Analysis (imea)
- **Features**: 16 per lesion
  - Fractal Dimension: 8 (3 planes × mean/median + 3D average)
  - Lacunarity: 8 (3 planes × mean/median + 3D average)
- **Methods**: Box-counting (FD), Gliding-box (Lacunarity)
- **Runtime**: ~1-2 min per scan
- **Note**: Most meaningful for irregular boundaries, not spherical ROIs

---

## GPU Configuration

**GPUs Used**: Device IDs 0 and 1 (NVIDIA runtime)

**Parallel Processing Strategy**:
- **Part 1** (N4): 4 subjects in parallel (CPU-bound, minimal GPU use)
- **Part 2** (HD-BET): 2 subjects in parallel (1 per GPU, ~8GB VRAM each)

**Environment Variables** (in container):
```bash
CUDA_VISIBLE_DEVICES=0,1
NVIDIA_VISIBLE_DEVICES=0,1
```

**Performance**:
- Sequential (CPU-only): ~18-22 hours for 66 scans
- GPU-accelerated parallel: ~2.5-3 hours
- **Speedup**: ~7-8x

---

## Feature Extraction

### Extract Radiomics
```bash
# Test data (4 scans)
python3 scripts/extract_radiomics.py test_patients results/radiomics.csv

# Full dataset (66 scans)
python3 scripts/extract_radiomics.py patients results/radiomics_all.csv
```

**Output CSV**:
- Columns: `subject_id`, `subject_num`, `sequence` + 1,409 feature columns
- Feature naming: `{image_type}_{feature_class}_{feature_name}`
- Example: `original_firstorder_Mean`, `wavelet-LLH_glcm_Contrast`

### Extract Fractal Metrics
```bash
# Test data
python3 scripts/extract_fractal.py test_patients results/fractal.csv

# Full dataset
python3 scripts/extract_fractal.py patients results/fractal_all.csv
```

**Output CSV**:
- Columns: `subject_id`, `subject_num`, `sequence` + 16 feature columns
- Features: `fd_axial_mean`, `fd_3d_mean`, `lac_coronal_median`, etc.

---

## Usage Examples

### Process Single Subject
```bash
# Part 1: Bias correction
./scripts/mri_preprocess_part1.sh sub-6_T1w test_patients

# Manually create lesion mask (see Manual Segmentation section)

# Part 2: Registration, skull-strip, normalize
./scripts/mri_preprocess_part2.sh sub-6_T1w test_patients
```

### Batch Processing (Recommended)
```bash
# Test dataset (4 scans) - run BOTH parts
./scripts/run_pipeline_parallel.sh test_patients both
# Creates lesion masks when prompted (or skip and create manually later)

# Full dataset (66 scans) - Part 1 only
./scripts/run_pipeline_parallel.sh patients part1

# Create all lesion masks manually (see below)

# Full dataset - Part 2 only (after masks are ready)
./scripts/run_pipeline_parallel.sh patients part2
```

### Check Outputs
```bash
# List final preprocessed images
ls -lh test_patients/*/Output_Part2/*_Step4_ZScore.nii.gz

# Check job logs
cat logs/test_patients_part1.log
cat logs/test_patients_part2.log
```

---

## Manual Segmentation (Optional)

**Required**: Lesion masks must be created before running Part 2.

### Option 1: ITK-SNAP via VNC (in Docker)

```bash
# Start VNC server (inside container)
./scripts/start_vnc.sh
# Set password when prompted

# From your local machine
ssh -L 5901:localhost:5901 user@gpuserver

# Open VNC client
# Connect to: localhost:5901
# Password: <what you set>

# In ITK-SNAP:
# 1. Load: test_patients/sub-6_T1w/Output_Part1/sub-6_T1w_Step1_BFC.nii.gz
# 2. Draw lesion mask
# 3. Save as: test_patients/sub-6_T1w/Lesion_Mask/sub-6_T1w_lesion_mask.nii.gz
```

### Option 2: ITK-SNAP on Host via SSH X11

```bash
# From local machine (with X11 forwarding)
ssh -X user@gpuserver
cd /path/to/FractalCavernoma
itksnap test_patients/sub-6_T1w/Output_Part1/sub-6_T1w_Step1_BFC.nii.gz
```

### Option 3: 3D Slicer or FSLeyes

```bash
# 3D Slicer (recommended, modern UI)
slicer test_patients/sub-6_T1w/Output_Part1/sub-6_T1w_Step1_BFC.nii.gz

# FSLeyes (lightweight)
fsleyes test_patients/sub-6_T1w/Output_Part1/sub-6_T1w_Step1_BFC.nii.gz
```

**Mask naming convention**:
- Must match: `{subject_id}_lesion_mask.nii.gz`
- Example: `sub-6_T1w_lesion_mask.nii.gz` (NOT `sub-006_T1w_lesion_mask.nii.gz`)
- Location: `Lesion_Mask/` folder

---

## Software Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| CUDA | 12.2.0 | GPU runtime |
| PyTorch | 2.0.1+cu118 | HD-BET backend |
| ANTs | 2.5.0 | N4, registration |
| HD-BET | 2.0.1 | GPU skull stripping |
| PyRadiomics | 3.0.1 | Feature extraction |
| imea | latest | Fractal analysis |
| nibabel | 5.2.0 | NIfTI I/O |
| SimpleITK | 2.3.1 | Image processing |
| scikit-learn | 1.3.2 | ML utilities |
| pandas | 2.1.4 | Data handling |

---

## Troubleshooting

### GPU Not Detected
```bash
# Check NVIDIA runtime
docker exec fractal-cavernoma-pipeline nvidia-smi

# Should show GPUs 0 and 1
```

### HD-BET Out of Memory
```bash
# Reduce parallel jobs in run_pipeline_parallel.sh
# Line 127: Change `-j 2` to `-j 1` (one GPU at a time)
parallel -j 1 --bar --joblog "${PATIENTS_DIR}_part2.log" \
    'run_part2 {} $(( {%} % 2 )) '"${PATIENTS_DIR}" ::: "${SUBJECTS[@]}"
```

### Missing Lesion Mask Error
```
ERROR: Missing lesion masks for the following subjects:
  - sub-6_T1w
```
**Fix**: Create mask in `Lesion_Mask/` folder with correct naming (see Manual Segmentation)

### N4BiasFieldCorrection Not Found
```bash
# Check PATH
docker exec fractal-cavernoma-pipeline echo $PATH
# Should include: /opt/ants/bin

# Verify ANTs installation
docker exec fractal-cavernoma-pipeline ls /opt/ants/bin/
```

### VNC Connection Refused
```bash
# Check VNC is running
docker exec fractal-cavernoma-pipeline ps aux | grep vnc

# Restart VNC
docker exec fractal-cavernoma-pipeline vncserver -kill :1
docker exec fractal-cavernoma-pipeline ./scripts/start_vnc.sh
```

---

## Performance Benchmarks

**Test Dataset (4 scans)**:
- Part 1: ~2 min total (4 parallel)
- Part 2: ~10 min total (2 parallel, GPU)
- Radiomics: ~10 min total
- Fractal: ~6 min total
- **Total**: ~30 min

**Full Dataset (66 scans)**:
- Part 1: ~30 min total
- Part 2: ~2.5 hours total (GPU)
- Radiomics: ~3 hours total
- Fractal: ~2 hours total
- **Total**: ~8 hours (vs ~40 hours CPU-only)

---

## Citation

**Methods adapted from**:
- Fractal analysis: [Fractal-Dimension-and-Lacunarity-in-Gliomas](https://github.com/nibr-lab/Fractal-Dimension-and-Lacunarity-in-Gliomas)
- HD-BET: Isensee et al., *arXiv:1901.11341*, 2019
- PyRadiomics: van Griethuysen et al., *Cancer Research*, 2017
- ANTs: Avants et al., *NeuroImage*, 2011

**Dataset**: Cambridge Centre for Ageing and Neuroscience (CamCAN) - OpenNeuro

---

## Next Steps

1. ✅ Run pipeline on test data (4 scans)
2. ✅ Extract radiomics + fractal features
3. ⏭ Create lesion masks for full dataset (66 scans)
4. ⏭ Run full pipeline (patients/)
5. ⏭ Feature selection (correlation analysis, variance filtering)
6. ⏭ Statistical analysis (T1w vs FLAIR, clinical correlations)
7. ⏭ Machine learning (classification, survival prediction)

---

## Contact

For detailed structure documentation, see [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)
