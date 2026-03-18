#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# USAGE: ./mri_preprocess_part2.sh <subject_id> [patients_dir]
# EXAMPLE: ./mri_preprocess_part2.sh sub-006_T1w
# EXAMPLE: ./mri_preprocess_part2.sh sub-006_FLAIR test_patients
# BATCH:   for subject in patients/sub-*/; do ./mri_preprocess_part2.sh "$(basename "$subject")"; done
# BATCH:   for subject in test_patients/sub-*/; do ./mri_preprocess_part2.sh "$(basename "$subject")" test_patients; done
# ---------------------------------------------------------------------------

# Check that a subject ID argument was provided
if [ $# -eq 0 ]; then
    echo "ERROR: No subject ID provided."
    echo "USAGE: ./mri_preprocess_part2.sh <subject_id> [patients_dir]"
    echo "EXAMPLE: ./mri_preprocess_part2.sh sub-006_T1w"
    echo "EXAMPLE: ./mri_preprocess_part2.sh sub-006_FLAIR test_patients"
    exit 1
fi

SUBJECT_ID="$1"
PATIENTS_DIR="${2:-patients}"  # Default to 'patients' if not specified

# Always operate relative to workspace root
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Paths based on subject ID
SUBJECT_DIR="${PATIENTS_DIR}/${SUBJECT_ID}"
OUT_DIR_PART1="${SUBJECT_DIR}/Output_Part1"
OUT_DIR_PART2="${SUBJECT_DIR}/Output_Part2"
MNI_REF="${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz"
LESION_MASK="${SUBJECT_DIR}/Lesion_Mask/${SUBJECT_ID}_lesion_mask.nii.gz"
STEP1="${OUT_DIR_PART1}/${SUBJECT_ID}_Step1_BFC.nii.gz"

# Check that the subject folder exists
[ -d "$SUBJECT_DIR" ] || { echo "ERROR: Subject folder not found: $SUBJECT_DIR — please run mri_preprocess_part1.sh first"; exit 1; }

# Check that Output_Part1 exists
[ -d "$OUT_DIR_PART1" ] || { echo "ERROR: Output_Part1 folder not found: $OUT_DIR_PART1 — please run mri_preprocess_part1.sh first"; exit 1; }

# Check that Step 1 output exists
[ -f "$STEP1" ] || { echo "ERROR: Step 1 output not found: $STEP1 — please run mri_preprocess_part1.sh first"; exit 1; }

mkdir -p "$OUT_DIR_PART2"

# Sanity checks
command -v antsRegistration >/dev/null || { echo "ERROR: antsRegistration not found"; exit 1; }
command -v ImageMath >/dev/null || { echo "ERROR: ImageMath not found"; exit 1; }
command -v antsApplyTransforms >/dev/null || { echo "ERROR: antsApplyTransforms not found"; exit 1; }
command -v hd-bet >/dev/null || { echo "ERROR: hd-bet not found"; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 not found"; exit 1; }
python3 -c "import nibabel" 2>/dev/null || { echo "ERROR: nibabel Python library not found"; exit 1; }
python3 -c "import numpy" 2>/dev/null || { echo "ERROR: numpy Python library not found"; exit 1; }

[ -f "$MNI_REF" ] || { echo "ERROR: MNI template not found: $MNI_REF"; exit 1; }
[ -f "$LESION_MASK" ] || { echo "ERROR: Lesion mask not found: $LESION_MASK — please complete the manual segmentation step first"; exit 1; }

echo "Processing subject: ${SUBJECT_ID}"
echo ""

# Invert the lesion mask so that ANTs uses the whole brain except the lesion for registration
echo "Inverting lesion mask..."
LESION_MASK_INV="$OUT_DIR_PART2/${SUBJECT_ID}_lesion_mask_inverted.nii.gz"
ImageMath 3 "$LESION_MASK_INV" Neg "$LESION_MASK"
echo "Inverted lesion mask saved to: $LESION_MASK_INV"
echo ""

echo "Step 2: Spatial normalisation to MNI (ANTs: rigid+affine, Linear interp, with inverted lesion mask)"
STEP2="$OUT_DIR_PART2/${SUBJECT_ID}_Step2_SpaceNorm.nii.gz"
ANTSPREFIX="$OUT_DIR_PART2/${SUBJECT_ID}_Step2_"
MAT="${ANTSPREFIX}0GenericAffine.mat"

antsRegistration \
  --dimensionality 3 \
  --float 0 \
  --output ["${ANTSPREFIX}","$STEP2"] \
  --interpolation Linear \
  --winsorize-image-intensities [0.005,0.995] \
  --use-histogram-matching 0 \
  --initial-moving-transform ["$MNI_REF","$STEP1",1] \
  --masks ["$MNI_REF","$LESION_MASK_INV"] \
  --transform Rigid[0.1] \
    --metric MI["$MNI_REF","$STEP1",1,32,Regular,0.25] \
    --convergence [1000x500x250x0,1e-6,10] \
    --shrink-factors 8x4x2x1 \
    --smoothing-sigmas 3x2x1x0vox \
  --transform Affine[0.1] \
    --metric MI["$MNI_REF","$STEP1",1,32,Regular,0.25] \
    --convergence [1000x500x250x0,1e-6,10] \
    --shrink-factors 8x4x2x1 \
    --smoothing-sigmas 3x2x1x0vox

[ -f "$MAT" ] || { echo "ERROR: Expected ANTs affine not found: $MAT"; exit 1; }

echo "Step 3: Skull stripping (HD-BET with GPU acceleration)"
STEP3="$OUT_DIR_PART2/${SUBJECT_ID}_Step3_SkullStrip.nii.gz"
HDBET_TMP="$OUT_DIR_PART2/${SUBJECT_ID}_Step3_tmp.nii.gz"

# Use GPU if available, fallback to CPU
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    echo "  Using GPU for HD-BET"
    hd-bet -i "$STEP2" -o "$HDBET_TMP" -device cuda --disable_tta
else
    echo "  GPU not available, using CPU for HD-BET"
    hd-bet -i "$STEP2" -o "$HDBET_TMP" -device cpu --disable_tta
fi

mv "$HDBET_TMP" "$STEP3"
echo "Skull stripped image saved to: $STEP3"

echo "Warping lesion mask into MNI space..."
LESION_MASK_MNI="$OUT_DIR_PART2/${SUBJECT_ID}_lesion_mask_MNI.nii.gz"
antsApplyTransforms \
  --dimensionality 3 \
  --input "$LESION_MASK" \
  --reference-image "$STEP2" \
  --output "$LESION_MASK_MNI" \
  --interpolation NearestNeighbor \
  --transform "$MAT"
echo "Lesion mask warped to MNI space: $LESION_MASK_MNI"

echo "Step 4: Z-score intensity normalisation (lesion excluded from mean and std calculation)"
STEP4="$OUT_DIR_PART2/${SUBJECT_ID}_Step4_ZScore.nii.gz"
NORM_MASK="$OUT_DIR_PART2/${SUBJECT_ID}_normalisation_mask.nii.gz"
python3 "$ROOT/scripts/zscore_normalise.py" "$STEP3" "$STEP4" "$LESION_MASK_MNI" "$NORM_MASK"

echo ""
echo "PART 2 DONE for ${SUBJECT_ID}. Outputs written to: $OUT_DIR_PART2"