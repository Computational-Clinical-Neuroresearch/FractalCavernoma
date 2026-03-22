#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# USAGE: ./mri_preprocess_part2.sh <subject_id> [patients_dir]
# EXAMPLE: ./mri_preprocess_part2.sh sub-001 patients
# BATCH:   for subject in patients/sub-*/; do ./mri_preprocess_part2.sh "$(basename "$subject")" patients; done
# ---------------------------------------------------------------------------

# Check that a subject ID argument was provided
if [ $# -eq 0 ]; then
    echo "ERROR: No subject ID provided."
    echo "USAGE: ./mri_preprocess_part2.sh <subject_id> [patients_dir]"
    echo "EXAMPLE: ./mri_preprocess_part2.sh sub-001 patients"
    exit 1
fi

SUBJECT_ID="$1"
PATIENTS_DIR="${2:-patients}"  # Default to 'patients' if not provided

# Always operate relative to workspace root
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Paths based on subject ID
SUBJECT_DIR="${PATIENTS_DIR}/${SUBJECT_ID}"
OUT_DIR_PART1="${SUBJECT_DIR}/Output_Part1"
OUT_DIR_PART2="${SUBJECT_DIR}/Output_Part2"
MNI_REF="${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz"
LESION_MASK="${SUBJECT_DIR}/Lesion_Mask/${SUBJECT_ID}_lesion_mask.nii.gz"

# Part 1 outputs used as inputs here
T1_STEP1="${OUT_DIR_PART1}/${SUBJECT_ID}_T1_Step1_BFC.nii.gz"
FLAIR_STEP1="${OUT_DIR_PART1}/${SUBJECT_ID}_FLAIR_Step1_BFC.nii.gz"

# Check that the subject folder exists
[ -d "$SUBJECT_DIR" ] || { echo "ERROR: Subject folder not found: $SUBJECT_DIR — please run mri_preprocess_part1.sh first"; exit 1; }

# Check that Output_Part1 exists
[ -d "$OUT_DIR_PART1" ] || { echo "ERROR: Output_Part1 folder not found: $OUT_DIR_PART1 — please run mri_preprocess_part1.sh first"; exit 1; }

# Check that Step 1 outputs exist
[ -f "$T1_STEP1" ] || { echo "ERROR: T1 Step 1 output not found: $T1_STEP1 — please run mri_preprocess_part1.sh first"; exit 1; }
[ -f "$FLAIR_STEP1" ] || { echo "ERROR: FLAIR Step 1 output not found: $FLAIR_STEP1 — please run mri_preprocess_part1.sh first"; exit 1; }

mkdir -p "$OUT_DIR_PART2"

# Sanity checks
command -v antsRegistration >/dev/null || { echo "ERROR: antsRegistration not found (activate conda env?)"; exit 1; }
command -v ImageMath >/dev/null || { echo "ERROR: ImageMath not found (activate conda env?)"; exit 1; }
command -v antsApplyTransforms >/dev/null || { echo "ERROR: antsApplyTransforms not found (activate conda env?)"; exit 1; }
command -v hd-bet >/dev/null || { echo "ERROR: hd-bet not found (activate conda env?)"; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 not found (activate conda env?)"; exit 1; }
python3 -c "import nibabel" 2>/dev/null || { echo "ERROR: nibabel Python library not found (activate conda env?)"; exit 1; }
python3 -c "import numpy" 2>/dev/null || { echo "ERROR: numpy Python library not found (activate conda env?)"; exit 1; }

[ -f "$MNI_REF" ] || { echo "ERROR: MNI template not found: $MNI_REF"; exit 1; }
[ -f "$LESION_MASK" ] || { echo "ERROR: Lesion mask not found: $LESION_MASK — please complete the manual segmentation step first"; exit 1; }

echo "Processing subject: ${SUBJECT_ID}"
echo ""

# ---------------------------------------------------------------------------
# LESION MASK INVERSION
# ---------------------------------------------------------------------------
echo "Inverting lesion mask..."
LESION_MASK_INV="$OUT_DIR_PART2/${SUBJECT_ID}_lesion_mask_inverted.nii.gz"
ImageMath 3 "$LESION_MASK_INV" Neg "$LESION_MASK"
echo "Inverted lesion mask saved to: $LESION_MASK_INV"
echo ""

# ---------------------------------------------------------------------------
# T1 PROCESSING
# ---------------------------------------------------------------------------

echo "--- T1 PROCESSING ---"
echo ""

echo "T1 Step 2: Spatial normalisation to MNI (ANTs: rigid+affine, Linear interp, with inverted lesion mask)"
T1_STEP2="$OUT_DIR_PART2/${SUBJECT_ID}_T1_Step2_SpaceNorm.nii.gz"
T1_ANTSPREFIX="$OUT_DIR_PART2/${SUBJECT_ID}_T1_Step2_"
T1_MAT="${T1_ANTSPREFIX}0GenericAffine.mat"

antsRegistration \
  --dimensionality 3 \
  --float 0 \
  --output ["${T1_ANTSPREFIX}","$T1_STEP2"] \
  --interpolation Linear \
  --winsorize-image-intensities [0.005,0.995] \
  --use-histogram-matching 0 \
  --initial-moving-transform ["$MNI_REF","$T1_STEP1",1] \
  --masks ["$MNI_REF","$LESION_MASK_INV"] \
  --transform Rigid[0.1] \
    --metric MI["$MNI_REF","$T1_STEP1",1,32,Regular,0.25] \
    --convergence [1000x500x250x0,1e-6,10] \
    --shrink-factors 8x4x2x1 \
    --smoothing-sigmas 3x2x1x0vox \
  --transform Affine[0.1] \
    --metric MI["$MNI_REF","$T1_STEP1",1,32,Regular,0.25] \
    --convergence [1000x500x250x0,1e-6,10] \
    --shrink-factors 8x4x2x1 \
    --smoothing-sigmas 3x2x1x0vox

[ -f "$T1_MAT" ] || { echo "ERROR: Expected T1 ANTs affine not found: $T1_MAT"; exit 1; }

echo "T1 Step 3: Skull stripping (HD-BET)"
T1_STEP3="$OUT_DIR_PART2/${SUBJECT_ID}_T1_Step3_SkullStrip.nii.gz"
T1_HDBET_TMP="$OUT_DIR_PART2/${SUBJECT_ID}_T1_Step3_tmp.nii.gz"

# Use GPU if available, fallback to CPU
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    echo "  Using GPU for HD-BET"
    hd-bet -i "$T1_STEP2" -o "$T1_HDBET_TMP" -device cuda --disable_tta
else
    echo "  GPU not available, using CPU for HD-BET"
    hd-bet -i "$T1_STEP2" -o "$T1_HDBET_TMP" -device cpu --disable_tta
fi

mv "$T1_HDBET_TMP" "$T1_STEP3"
echo "T1 skull stripped image saved to: $T1_STEP3"

# Derive binary brain mask from T1 skull stripped image
# This mask will be used to skull strip all other modalities
T1_BRAIN_MASK="$OUT_DIR_PART2/${SUBJECT_ID}_T1_BrainMask.nii.gz"
python3 - <<EOF
import nibabel as nib
import numpy as np
img = nib.load("$T1_STEP3")
data = img.get_fdata()
mask = (data > 0).astype(np.float32)
mask_img = nib.Nifti1Image(mask, img.affine, img.header)
nib.save(mask_img, "$T1_BRAIN_MASK")
print("T1 brain mask saved to: $T1_BRAIN_MASK")
EOF

echo "T1 Step 4: Z-score intensity normalisation (lesion excluded from mean and std calculation)"
# Warp lesion mask into MNI space using T1 registration transform
LESION_MASK_MNI="$OUT_DIR_PART2/${SUBJECT_ID}_lesion_mask_MNI.nii.gz"
antsApplyTransforms \
  --dimensionality 3 \
  --input "$LESION_MASK" \
  --reference-image "$T1_STEP2" \
  --output "$LESION_MASK_MNI" \
  --interpolation NearestNeighbor \
  --transform "$T1_MAT"
echo "Lesion mask warped to MNI space: $LESION_MASK_MNI"

T1_STEP4="$OUT_DIR_PART2/${SUBJECT_ID}_T1_Step4_ZScore.nii.gz"
T1_NORM_MASK="$OUT_DIR_PART2/${SUBJECT_ID}_T1_normalisation_mask.nii.gz"
python3 "$ROOT/scripts/zscore_normalise.py" "$T1_STEP3" "$T1_STEP4" "$LESION_MASK_MNI" "$T1_NORM_MASK"
echo ""

# ---------------------------------------------------------------------------
# FLAIR PROCESSING
# ---------------------------------------------------------------------------

echo "--- FLAIR PROCESSING ---"
echo ""

echo "FLAIR Step 2a: Co-registration to T1 (ANTs: rigid+affine)"
FLAIR_STEP2A="$OUT_DIR_PART2/${SUBJECT_ID}_FLAIR_Step2a_CoregToT1.nii.gz"
FLAIR_ANTSPREFIX="$OUT_DIR_PART2/${SUBJECT_ID}_FLAIR_Step2a_"
FLAIR_MAT="${FLAIR_ANTSPREFIX}0GenericAffine.mat"

antsRegistration \
  --dimensionality 3 \
  --float 0 \
  --output ["${FLAIR_ANTSPREFIX}","$FLAIR_STEP2A"] \
  --interpolation Linear \
  --winsorize-image-intensities [0.005,0.995] \
  --use-histogram-matching 0 \
  --initial-moving-transform ["$T1_STEP1","$FLAIR_STEP1",1] \
  --transform Rigid[0.1] \
    --metric MI["$T1_STEP1","$FLAIR_STEP1",1,32,Regular,0.25] \
    --convergence [1000x500x250x0,1e-6,10] \
    --shrink-factors 8x4x2x1 \
    --smoothing-sigmas 3x2x1x0vox \
  --transform Affine[0.1] \
    --metric MI["$T1_STEP1","$FLAIR_STEP1",1,32,Regular,0.25] \
    --convergence [1000x500x250x0,1e-6,10] \
    --shrink-factors 8x4x2x1 \
    --smoothing-sigmas 3x2x1x0vox

[ -f "$FLAIR_MAT" ] || { echo "ERROR: Expected FLAIR ANTs affine not found: $FLAIR_MAT"; exit 1; }

echo "FLAIR Step 2b: Applying combined FLAIR-to-T1 and T1-to-MNI transforms to bring FLAIR into MNI space"
FLAIR_STEP2B="$OUT_DIR_PART2/${SUBJECT_ID}_FLAIR_Step2b_MNI.nii.gz"
antsApplyTransforms \
  --dimensionality 3 \
  --input "$FLAIR_STEP1" \
  --reference-image "$MNI_REF" \
  --output "$FLAIR_STEP2B" \
  --interpolation Linear \
  --transform "$T1_MAT" \
  --transform "$FLAIR_MAT"
echo "FLAIR in MNI space saved to: $FLAIR_STEP2B"

echo "FLAIR Step 3: Skull stripping (applying T1 brain mask)"
FLAIR_STEP3="$OUT_DIR_PART2/${SUBJECT_ID}_FLAIR_Step3_SkullStrip.nii.gz"
python3 - <<EOF
import nibabel as nib
import numpy as np
flair_img = nib.load("$FLAIR_STEP2B")
mask_img = nib.load("$T1_BRAIN_MASK")
flair_data = flair_img.get_fdata()
mask_data = mask_img.get_fdata()
skull_stripped = flair_data * mask_data
out_img = nib.Nifti1Image(skull_stripped.astype(np.float32), flair_img.affine, flair_img.header)
nib.save(out_img, "$FLAIR_STEP3")
print("FLAIR skull stripped image saved to: $FLAIR_STEP3")
EOF

echo "FLAIR Step 4: Z-score intensity normalisation (lesion excluded from mean and std calculation)"
FLAIR_STEP4="$OUT_DIR_PART2/${SUBJECT_ID}_FLAIR_Step4_ZScore.nii.gz"
FLAIR_NORM_MASK="$OUT_DIR_PART2/${SUBJECT_ID}_FLAIR_normalisation_mask.nii.gz"
python3 "$ROOT/scripts/zscore_normalise.py" "$FLAIR_STEP3" "$FLAIR_STEP4" "$LESION_MASK_MNI" "$FLAIR_NORM_MASK"

echo ""
echo "PART 2 DONE for ${SUBJECT_ID}. Outputs written to: $OUT_DIR_PART2"
