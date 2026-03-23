#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# USAGE: ./mri_preprocess.sh <subject_id>
# EXAMPLE: ./mri_preprocess.sh sub-001
# BATCH:   for subject in patients/sub-*/; do ./mri_preprocess.sh "$(basename "$subject")"; done
# ---------------------------------------------------------------------------

# Check that a subject ID argument was provided
if [ $# -eq 0 ]; then
    echo "ERROR: No subject ID provided."
    echo "USAGE: ./mri_preprocess.sh <subject_id>"
    echo "EXAMPLE: ./mri_preprocess.sh sub-001"
    exit 1
fi

SUBJECT_ID="$1"

# Always operate relative to the folder where this script lives (study root)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# ---------------------------------------------------------------------------
# PRE-EXECUTION LESION MASK CHECK
# Check all patients have a lesion mask before processing begins
# ---------------------------------------------------------------------------
echo "Checking lesion masks for all subjects..."
MISSING_MASKS=()
for subject_dir in patients/sub-*/; do
    subject="$(basename "$subject_dir")"
    mask="${subject_dir}Lesion_Mask/${subject}_lesion_mask.nii.gz"
    if [ ! -f "$mask" ]; then
        MISSING_MASKS+=("$subject")
    fi
done

if [ ${#MISSING_MASKS[@]} -gt 0 ]; then
    echo ""
    echo "ERROR: Lesion masks are missing for the following subjects:"
    for subject in "${MISSING_MASKS[@]}"; do
        echo "   - ${subject}"
    done
    echo ""
    echo "---------------------------------------------------------------------"
    echo "BEFORE RUNNING THIS SCRIPT, COMPLETE THE FOLLOWING MANUAL STEP:"
    echo ""
    echo "For each subject listed above without a lesion mask,"
    echo "open the raw input NIfTI image in ITK-SNAP. Use the T2 image:"
    echo "   Input_NIfTI/<subject_id>_T2.nii.gz"
    echo "   (If SWI is available for all patients in this study, use SWI rather than T2)"
    echo ""
    echo "Draw a spherical lesion mask around the cavernoma."
    echo "Save the mask to:"
    echo "   patients/<subject_id>/Lesion_Mask/<subject_id>_lesion_mask.nii.gz"
    echo ""
    echo "Note: The lesion mask should be drawn on the raw input NIfTI"
    echo "image before preprocessing."
    echo "The same spherical lesion mask will be automatically applied"
    echo "to all modalities during preprocessing."
    echo ""
    echo "Once all lesion masks are present, re-run this script."
    echo "---------------------------------------------------------------------"
    exit 1
fi

echo "All lesion masks present. Proceeding with preprocessing."
echo ""

# Paths based on subject ID
SUBJECT_DIR="patients/${SUBJECT_ID}"
INPUT_DIR="${SUBJECT_DIR}/Input_NIfTI"
OUT_DIR_INTERMEDIATE="${SUBJECT_DIR}/Output_Intermediate"
OUT_DIR_FINAL="${SUBJECT_DIR}/Output_Final"
MNI_REF="${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz"
LESION_MASK="${SUBJECT_DIR}/Lesion_Mask/${SUBJECT_ID}_lesion_mask.nii.gz"

# Check that the subject folder exists
[ -d "$SUBJECT_DIR" ] || { echo "ERROR: Subject folder not found: $SUBJECT_DIR"; exit 1; }
[ -d "$INPUT_DIR" ] || { echo "ERROR: Input_NIfTI folder not found: $INPUT_DIR"; exit 1; }

# ---------------------------------------------------------------------------
# DYNAMIC MODALITY DETECTION
# Scans Input_NIfTI folder for all NIfTI files belonging to this subject
# Extracts modality name from filename e.g. sub-001_T1.nii.gz -> T1
# ---------------------------------------------------------------------------
MODALITIES=()
for f in "$INPUT_DIR"/${SUBJECT_ID}_*.nii.gz "$INPUT_DIR"/${SUBJECT_ID}_*.nii; do
    [ -f "$f" ] || continue
    filename="$(basename "$f")"
    modality="${filename#${SUBJECT_ID}_}"
    modality="${modality%.nii.gz}"
    modality="${modality%.nii}"
    MODALITIES+=("$modality")
done

# Check at least one modality was found
if [ ${#MODALITIES[@]} -eq 0 ]; then
    echo "ERROR: No input NIfTI files found for ${SUBJECT_ID} in ${INPUT_DIR}"
    echo "Please ensure files are named: ${SUBJECT_ID}_<MODALITY>.nii.gz"
    echo "Example: ${SUBJECT_ID}_T1.nii.gz, ${SUBJECT_ID}_FLAIR.nii.gz"
    exit 1
fi

# Check T1 is present
T1_FOUND=0
for mod in "${MODALITIES[@]}"; do
    if [ "$mod" = "T1" ]; then
        T1_FOUND=1
        break
    fi
done
[ "$T1_FOUND" -eq 1 ] || { echo "ERROR: T1 modality not found in ${INPUT_DIR} — T1 is required for all subjects"; exit 1; }

# Separate T1 from other modalities
NON_T1_MODALITIES=()
for mod in "${MODALITIES[@]}"; do
    if [ "$mod" != "T1" ]; then
        NON_T1_MODALITIES+=("$mod")
    fi
done

# Print modality detection summary
NUM_MODALITIES=${#MODALITIES[@]}
MODALITY_LIST="$(IFS=", "; echo "${MODALITIES[*]}")"
echo "=========================================="
echo "Subject: ${SUBJECT_ID}"
echo "${NUM_MODALITIES} modalities detected: ${MODALITY_LIST}"
echo "T1 will be processed first, followed by: $(IFS=", "; echo "${NON_T1_MODALITIES[*]:-none}")"
echo "=========================================="
echo ""

mkdir -p "$OUT_DIR_INTERMEDIATE"
mkdir -p "$OUT_DIR_FINAL"

# Sanity checks
command -v N4BiasFieldCorrection >/dev/null || { echo "ERROR: N4BiasFieldCorrection not found (activate conda env?)"; exit 1; }
command -v antsRegistration >/dev/null || { echo "ERROR: antsRegistration not found (activate conda env?)"; exit 1; }
command -v ImageMath >/dev/null || { echo "ERROR: ImageMath not found (activate conda env?)"; exit 1; }
command -v antsApplyTransforms >/dev/null || { echo "ERROR: antsApplyTransforms not found (activate conda env?)"; exit 1; }
command -v hd-bet >/dev/null || { echo "ERROR: hd-bet not found (activate conda env?)"; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 not found (activate conda env?)"; exit 1; }
python3 -c "import nibabel" 2>/dev/null || { echo "ERROR: nibabel Python library not found (activate conda env?)"; exit 1; }
python3 -c "import numpy" 2>/dev/null || { echo "ERROR: numpy Python library not found (activate conda env?)"; exit 1; }

[ -f "$MNI_REF" ] || { echo "ERROR: MNI template not found: $MNI_REF"; exit 1; }
[ -f "$LESION_MASK" ] || { echo "ERROR: Lesion mask not found: $LESION_MASK"; exit 1; }

echo "Processing subject: ${SUBJECT_ID}"
echo ""

# ---------------------------------------------------------------------------
# BIAS FIELD CORRECTION FOR ALL MODALITIES
# ---------------------------------------------------------------------------
for MODALITY in "${MODALITIES[@]}"; do
    if [ -f "${INPUT_DIR}/${SUBJECT_ID}_${MODALITY}.nii.gz" ]; then
        INPUT_FILE="${INPUT_DIR}/${SUBJECT_ID}_${MODALITY}.nii.gz"
    elif [ -f "${INPUT_DIR}/${SUBJECT_ID}_${MODALITY}.nii" ]; then
        INPUT_FILE="${INPUT_DIR}/${SUBJECT_ID}_${MODALITY}.nii"
    else
        echo "ERROR: Input file not found for modality ${MODALITY}"
        exit 1
    fi

    echo "Step 1: Bias field correction (N4) — ${MODALITY}"
    OUTPUT_FILE="$OUT_DIR_INTERMEDIATE/${SUBJECT_ID}_${MODALITY}_Step1_BFC.nii.gz"
    N4BiasFieldCorrection -d 3 -i "$INPUT_FILE" -s 3 -c [100x50x20,0.000001] -o "$OUTPUT_FILE"
    echo "${MODALITY} bias field corrected image saved to: $OUTPUT_FILE"
    echo ""
done

# ---------------------------------------------------------------------------
# LESION MASK INVERSION
# ---------------------------------------------------------------------------
echo "Inverting lesion mask..."
LESION_MASK_INV="$OUT_DIR_INTERMEDIATE/${SUBJECT_ID}_lesion_mask_inverted.nii.gz"
ImageMath 3 "$LESION_MASK_INV" Neg "$LESION_MASK"
echo "Inverted lesion mask saved to: $LESION_MASK_INV"
echo ""

# ---------------------------------------------------------------------------
# T1 PROCESSING
# ---------------------------------------------------------------------------

echo "--- T1 PROCESSING ---"
echo ""

T1_STEP1="${OUT_DIR_INTERMEDIATE}/${SUBJECT_ID}_T1_Step1_BFC.nii.gz"
[ -f "$T1_STEP1" ] || { echo "ERROR: T1 Step 1 output not found: $T1_STEP1"; exit 1; }

echo "T1 Step 2: Spatial normalisation to MNI (ANTs: rigid+affine, Linear interp, with inverted lesion mask)"
T1_STEP2="$OUT_DIR_INTERMEDIATE/${SUBJECT_ID}_T1_Step2_SpaceNorm.nii.gz"
T1_ANTSPREFIX="$OUT_DIR_INTERMEDIATE/${SUBJECT_ID}_T1_Step2_"
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
T1_STEP3="$OUT_DIR_INTERMEDIATE/${SUBJECT_ID}_T1_Step3_SkullStrip.nii.gz"
T1_HDBET_TMP="$OUT_DIR_INTERMEDIATE/${SUBJECT_ID}_T1_Step3_tmp.nii.gz"

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
T1_BRAIN_MASK="$OUT_DIR_INTERMEDIATE/${SUBJECT_ID}_T1_BrainMask.nii.gz"
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

# Warp lesion mask into MNI space using T1 registration transform
echo "Warping lesion mask into MNI space..."
LESION_MASK_MNI="$OUT_DIR_INTERMEDIATE/${SUBJECT_ID}_lesion_mask_MNI.nii.gz"
antsApplyTransforms \
  --dimensionality 3 \
  --input "$LESION_MASK" \
  --reference-image "$T1_STEP2" \
  --output "$LESION_MASK_MNI" \
  --interpolation NearestNeighbor \
  --transform "$T1_MAT"
echo "Lesion mask warped to MNI space: $LESION_MASK_MNI"

echo "T1 Step 4: Z-score intensity normalisation (lesion excluded from mean and std calculation)"
T1_STEP4="$OUT_DIR_FINAL/${SUBJECT_ID}_T1_Step4_ZScore.nii.gz"
T1_NORM_MASK="$OUT_DIR_INTERMEDIATE/${SUBJECT_ID}_T1_normalisation_mask.nii.gz"
python3 "$ROOT/zscore_normalise.py" "$T1_STEP3" "$T1_STEP4" "$LESION_MASK_MNI" "$T1_NORM_MASK"
echo "T1 processing complete."
echo ""

# ---------------------------------------------------------------------------
# NON-T1 MODALITY PROCESSING LOOP
# Each non-T1 modality goes through:
# Step 2a: Co-registration to T1
# Step 2b: Apply combined transform to MNI space
# Step 3:  Skull stripping using T1 brain mask
# Step 4:  Z-score intensity normalisation
# ---------------------------------------------------------------------------
for MODALITY in "${NON_T1_MODALITIES[@]}"; do

    echo "--- ${MODALITY} PROCESSING ---"
    echo ""

    MOD_STEP1="${OUT_DIR_INTERMEDIATE}/${SUBJECT_ID}_${MODALITY}_Step1_BFC.nii.gz"
    [ -f "$MOD_STEP1" ] || { echo "ERROR: Step 1 output not found for ${MODALITY}: $MOD_STEP1"; exit 1; }

    echo "${MODALITY} Step 2a: Co-registration to T1 (ANTs: rigid+affine)"
    MOD_STEP2A="$OUT_DIR_INTERMEDIATE/${SUBJECT_ID}_${MODALITY}_Step2a_CoregToT1.nii.gz"
    MOD_ANTSPREFIX="$OUT_DIR_INTERMEDIATE/${SUBJECT_ID}_${MODALITY}_Step2a_"
    MOD_MAT="${MOD_ANTSPREFIX}0GenericAffine.mat"

    antsRegistration \
      --dimensionality 3 \
      --float 0 \
      --output ["${MOD_ANTSPREFIX}","$MOD_STEP2A"] \
      --interpolation Linear \
      --winsorize-image-intensities [0.005,0.995] \
      --use-histogram-matching 0 \
      --initial-moving-transform ["$T1_STEP1","$MOD_STEP1",1] \
      --transform Rigid[0.1] \
        --metric MI["$T1_STEP1","$MOD_STEP1",1,32,Regular,0.25] \
        --convergence [1000x500x250x0,1e-6,10] \
        --shrink-factors 8x4x2x1 \
        --smoothing-sigmas 3x2x1x0vox \
      --transform Affine[0.1] \
        --metric MI["$T1_STEP1","$MOD_STEP1",1,32,Regular,0.25] \
        --convergence [1000x500x250x0,1e-6,10] \
        --shrink-factors 8x4x2x1 \
        --smoothing-sigmas 3x2x1x0vox

    [ -f "$MOD_MAT" ] || { echo "ERROR: Expected ${MODALITY} ANTs affine not found: $MOD_MAT"; exit 1; }

    echo "${MODALITY} Step 2b: Applying combined ${MODALITY}-to-T1 and T1-to-MNI transforms to bring ${MODALITY} into MNI space"
    MOD_STEP2B="$OUT_DIR_INTERMEDIATE/${SUBJECT_ID}_${MODALITY}_Step2b_MNI.nii.gz"
    antsApplyTransforms \
      --dimensionality 3 \
      --input "$MOD_STEP1" \
      --reference-image "$MNI_REF" \
      --output "$MOD_STEP2B" \
      --interpolation Linear \
      --transform "$T1_MAT" \
      --transform "$MOD_MAT"
    echo "${MODALITY} in MNI space saved to: $MOD_STEP2B"

    echo "${MODALITY} Step 3: Skull stripping (applying T1 brain mask)"
    MOD_STEP3="$OUT_DIR_INTERMEDIATE/${SUBJECT_ID}_${MODALITY}_Step3_SkullStrip.nii.gz"
    python3 - <<EOF
import nibabel as nib
import numpy as np
mod_img = nib.load("$MOD_STEP2B")
mask_img = nib.load("$T1_BRAIN_MASK")
mod_data = mod_img.get_fdata()
mask_data = mask_img.get_fdata()
skull_stripped = mod_data * mask_data
out_img = nib.Nifti1Image(skull_stripped.astype(np.float32), mod_img.affine, mod_img.header)
nib.save(out_img, "$MOD_STEP3")
print("${MODALITY} skull stripped image saved to: $MOD_STEP3")
EOF

    echo "${MODALITY} Step 4: Z-score intensity normalisation (lesion excluded from mean and std calculation)"
    MOD_STEP4="$OUT_DIR_FINAL/${SUBJECT_ID}_${MODALITY}_Step4_ZScore.nii.gz"
    MOD_NORM_MASK="$OUT_DIR_INTERMEDIATE/${SUBJECT_ID}_${MODALITY}_normalisation_mask.nii.gz"
    python3 "$ROOT/zscore_normalise.py" "$MOD_STEP3" "$MOD_STEP4" "$LESION_MASK_MNI" "$MOD_NORM_MASK"
    echo "${MODALITY} processing complete."
    echo ""

done

echo "=========================================="
echo "PREPROCESSING DONE for ${SUBJECT_ID}."
echo "Intermediate outputs: $OUT_DIR_INTERMEDIATE"
echo "Final outputs:        $OUT_DIR_FINAL"
echo "=========================================="
