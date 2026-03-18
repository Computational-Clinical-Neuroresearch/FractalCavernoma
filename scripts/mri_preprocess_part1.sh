#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# USAGE: ./mri_preprocess_part1.sh <subject_id> [patients_dir]
# EXAMPLE: ./mri_preprocess_part1.sh sub-006_T1w
# EXAMPLE: ./mri_preprocess_part1.sh sub-006_FLAIR test_patients
# BATCH:   for subject in patients/sub-*/; do ./mri_preprocess_part1.sh "$(basename "$subject")"; done
# BATCH:   for subject in test_patients/sub-*/; do ./mri_preprocess_part1.sh "$(basename "$subject")" test_patients; done
# ---------------------------------------------------------------------------

# Check that a subject ID argument was provided
if [ $# -eq 0 ]; then
    echo "ERROR: No subject ID provided."
    echo "USAGE: ./mri_preprocess_part1.sh <subject_id> [patients_dir]"
    echo "EXAMPLE: ./mri_preprocess_part1.sh sub-006_T1w"
    echo "EXAMPLE: ./mri_preprocess_part1.sh sub-006_FLAIR test_patients"
    exit 1
fi

SUBJECT_ID="$1"
PATIENTS_DIR="${2:-patients}"  # Default to 'patients' if not specified

# Always operate relative to workspace root
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Paths based on subject ID
SUBJECT_DIR="${PATIENTS_DIR}/${SUBJECT_ID}"
OUT_DIR="${SUBJECT_DIR}/Output_Part1"

# Check that the subject folder exists
[ -d "$SUBJECT_DIR" ] || { echo "ERROR: Subject folder not found: $SUBJECT_DIR"; exit 1; }

# Automatically detect whether input is .nii.gz or .nii
if [ -f "${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}.nii.gz" ]; then
    INPUT_NII="${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}.nii.gz"
elif [ -f "${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}.nii" ]; then
    INPUT_NII="${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}.nii"
else
    echo "ERROR: No input NIfTI found for ${SUBJECT_ID}."
    echo "Please ensure the file is named either:"
    echo "   ${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}.nii.gz"
    echo "   ${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}.nii"
    exit 1
fi
echo "Found input file: $INPUT_NII"

mkdir -p "$OUT_DIR"

# Sanity checks
command -v N4BiasFieldCorrection >/dev/null || { echo "ERROR: N4BiasFieldCorrection not found"; exit 1; }

echo "Processing subject: ${SUBJECT_ID}"
echo ""

echo "Step 1: Bias field correction (N4)"
STEP1="$OUT_DIR/${SUBJECT_ID}_Step1_BFC.nii.gz"
N4BiasFieldCorrection -d 3 -i "$INPUT_NII" -s 3 -c [100x50x20,0.000001] -o "$STEP1"

echo ""
echo "PART 1 DONE for ${SUBJECT_ID}. Output written to: $OUT_DIR"

# Print instructions only after the last subject has been processed
if [ -d "$PATIENTS_DIR" ]; then
    LAST_SUBJECT="$(ls -d ${PATIENTS_DIR}/sub-*/ 2>/dev/null | tail -n 1 | xargs basename 2>/dev/null || echo '')"
    if [ -n "$LAST_SUBJECT" ] && [ "$SUBJECT_ID" = "$LAST_SUBJECT" ]; then
        echo ""
        echo "---------------------------------------------------------------------"
        echo "ALL SUBJECTS PROCESSED. NEXT MANUAL STEP:"
        echo "1. Open each subject's bias corrected image in ITK-SNAP:"
        echo "   ${PATIENTS_DIR}/sub-006_T1w/Output_Part1/sub-006_T1w_Step1_BFC.nii.gz"
        echo "2. Draw a spherical lesion mask around the cavernoma"
        echo "3. Save the mask to:"
        echo "   ${PATIENTS_DIR}/sub-006_T1w/Lesion_Mask/sub-006_T1w_lesion_mask.nii.gz"
        echo "4. Repeat steps 1-3 for all subjects (both T1w and FLAIR sequences)"
        echo "5. Once all lesion masks are complete, run:"
        echo "   for subject in ${PATIENTS_DIR}/sub-*/; do ./mri_preprocess_part2.sh \"\$(basename \"\$subject\")\" \"$PATIENTS_DIR\"; done"
        echo "---------------------------------------------------------------------"
    fi
fi