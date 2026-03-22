#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# USAGE: ./mri_preprocess_part1.sh <subject_id> [patients_dir]
# EXAMPLE: ./mri_preprocess_part1.sh sub-001 patients
# BATCH:   for subject in patients/sub-*/; do ./mri_preprocess_part1.sh "$(basename "$subject")" patients; done
# ---------------------------------------------------------------------------

# Check that a subject ID argument was provided
if [ $# -eq 0 ]; then
    echo "ERROR: No subject ID provided."
    echo "USAGE: ./mri_preprocess_part1.sh <subject_id> [patients_dir]"
    echo "EXAMPLE: ./mri_preprocess_part1.sh sub-001 patients"
    exit 1
fi

SUBJECT_ID="$1"
PATIENTS_DIR="${2:-patients}"  # Default to 'patients' if not provided

# Always operate relative to workspace root
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Paths based on subject ID
SUBJECT_DIR="${PATIENTS_DIR}/${SUBJECT_ID}"
OUT_DIR="${SUBJECT_DIR}/Output_Part1"

# Check that the subject folder exists
[ -d "$SUBJECT_DIR" ] || { echo "ERROR: Subject folder not found: $SUBJECT_DIR"; exit 1; }

# Automatically detect whether T1 input is .nii.gz or .nii
if [ -f "${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}_T1.nii.gz" ]; then
    INPUT_T1="${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}_T1.nii.gz"
elif [ -f "${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}_T1.nii" ]; then
    INPUT_T1="${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}_T1.nii"
else
    echo "ERROR: No T1 input NIfTI found for ${SUBJECT_ID}."
    echo "Please ensure the file is named either:"
    echo "   ${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}_T1.nii.gz"
    echo "   ${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}_T1.nii"
    exit 1
fi
echo "Found T1 input file: $INPUT_T1"

# Automatically detect whether FLAIR input is .nii.gz or .nii
if [ -f "${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}_FLAIR.nii.gz" ]; then
    INPUT_FLAIR="${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}_FLAIR.nii.gz"
elif [ -f "${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}_FLAIR.nii" ]; then
    INPUT_FLAIR="${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}_FLAIR.nii"
else
    echo "ERROR: No FLAIR input NIfTI found for ${SUBJECT_ID}."
    echo "Please ensure the file is named either:"
    echo "   ${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}_FLAIR.nii.gz"
    echo "   ${SUBJECT_DIR}/Input_NIfTI/${SUBJECT_ID}_FLAIR.nii"
    exit 1
fi
echo "Found FLAIR input file: $INPUT_FLAIR"

mkdir -p "$OUT_DIR"

# Sanity checks
command -v N4BiasFieldCorrection >/dev/null || { echo "ERROR: N4BiasFieldCorrection not found (activate conda env?)"; exit 1; }

echo "Processing subject: ${SUBJECT_ID}"
echo ""

echo "Step 1: Bias field correction (N4) — T1"
T1_STEP1="$OUT_DIR/${SUBJECT_ID}_T1_Step1_BFC.nii.gz"
N4BiasFieldCorrection -d 3 -i "$INPUT_T1" -s 3 -c [100x50x20,0.000001] -o "$T1_STEP1"
echo "T1 bias field corrected image saved to: $T1_STEP1"
echo ""

echo "Step 1: Bias field correction (N4) — FLAIR"
FLAIR_STEP1="$OUT_DIR/${SUBJECT_ID}_FLAIR_Step1_BFC.nii.gz"
N4BiasFieldCorrection -d 3 -i "$INPUT_FLAIR" -s 3 -c [100x50x20,0.000001] -o "$FLAIR_STEP1"
echo "FLAIR bias field corrected image saved to: $FLAIR_STEP1"
echo ""

echo "PART 1 DONE for ${SUBJECT_ID}. Outputs written to: $OUT_DIR"

# Print instructions only after the last subject has been processed
LAST_SUBJECT="$(ls -d patients/sub-*/ | tail -n 1 | xargs basename)"
if [ "$SUBJECT_ID" = "$LAST_SUBJECT" ]; then
    echo ""
    echo "---------------------------------------------------------------------"
    echo "ALL SUBJECTS PROCESSED. NEXT MANUAL STEP:"
    echo ""
    echo "For each subject, open the T1 bias corrected image in ITK-SNAP:"
    echo "   patients/sub-001/Output_Part1/sub-001_T1_Step1_BFC.nii.gz"
    echo ""
    echo "Draw a spherical lesion mask around the cavernoma."
    echo "Save the mask to:"
    echo "   patients/sub-001/Lesion_Mask/sub-001_lesion_mask.nii.gz"
    echo ""
    echo "Repeat for all other subjects (sub-002, sub-003, etc.)"
    echo ""
    echo "Note: Draw the lesion mask on the T1 image only. The same mask"
    echo "will be automatically applied to all other modalities (FLAIR etc.)"
    echo ""
    echo "Once all lesion masks are complete, run:"
    echo "   for subject in patients/sub-*/; do ./mri_preprocess_part2_MM.sh \"\$(basename \"\$subject\")\"; done"
    echo "---------------------------------------------------------------------"
fi
