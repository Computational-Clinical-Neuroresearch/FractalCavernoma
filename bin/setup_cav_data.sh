#!/usr/bin/env bash
set -euo pipefail

# Setup script to organize CAV patient data
# Creates folder structure for all CAV subjects (T1w and FLAIR) and a test subset

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# CAV subject IDs from metadata
CAV_SUBJECTS=(6 18 21 35 51 58 59 65 88 91 123 129 136 177 179 180 189 198 206 211 228 253 286 299 309 319 321 323 355 367 412 448 462)

# Test subjects (first 2 for quick pipeline testing)
TEST_SUBJECTS=(6 18)

echo "=========================================="
echo "Setting up CAV patient data structure"
echo "Total CAV subjects: ${#CAV_SUBJECTS[@]}"
echo "Test subjects: ${TEST_SUBJECTS[@]}"
echo "=========================================="
echo ""

# Function to copy subject data
copy_subject_data() {
    local subject_num=$1
    local dest_base=$2
    local subject_id="sub-${subject_num}"
    local source_dir="${ROOT}/raw_data/${subject_id}/ses-1/anat"

    if [ ! -d "$source_dir" ]; then
        echo "WARNING: Source directory not found for ${subject_id}, skipping..."
        return
    fi

    # Copy T1w
    local t1_source
    if [ -f "${source_dir}/${subject_id}_ses-1_T1w.nii.gz" ]; then
        t1_source="${source_dir}/${subject_id}_ses-1_T1w.nii.gz"
    elif [ -f "${source_dir}/${subject_id}_ses-1_T1w.nii" ]; then
        t1_source="${source_dir}/${subject_id}_ses-1_T1w.nii"
    else
        echo "WARNING: T1w not found for ${subject_id}"
        t1_source=""
    fi

    if [ -n "$t1_source" ]; then
        local t1_dest="${dest_base}/${subject_id}_T1w"
        mkdir -p "${t1_dest}/Input_NIfTI"
        local filename=$(basename "$t1_source")
        local extension="${filename#*T1w}"
        cp "$t1_source" "${t1_dest}/Input_NIfTI/${subject_id}_T1w${extension}"
        echo "  ✓ Copied T1w for ${subject_id}"
    fi

    # Copy FLAIR
    local flair_source
    if [ -f "${source_dir}/${subject_id}_ses-1_FLAIR.nii.gz" ]; then
        flair_source="${source_dir}/${subject_id}_ses-1_FLAIR.nii.gz"
    elif [ -f "${source_dir}/${subject_id}_ses-1_FLAIR.nii" ]; then
        flair_source="${source_dir}/${subject_id}_ses-1_FLAIR.nii"
    else
        echo "WARNING: FLAIR not found for ${subject_id}"
        flair_source=""
    fi

    if [ -n "$flair_source" ]; then
        local flair_dest="${dest_base}/${subject_id}_FLAIR"
        mkdir -p "${flair_dest}/Input_NIfTI"
        local filename=$(basename "$flair_source")
        local extension="${filename#*FLAIR}"
        cp "$flair_source" "${flair_dest}/Input_NIfTI/${subject_id}_FLAIR${extension}"
        echo "  ✓ Copied FLAIR for ${subject_id}"
    fi
}

# Create main patients directory
echo "Creating patients/ directory for all CAV subjects..."
mkdir -p "${ROOT}/patients"

for subject_num in "${CAV_SUBJECTS[@]}"; do
    copy_subject_data "$subject_num" "${ROOT}/patients"
done

echo ""
echo "✓ Main patients/ directory created with ${#CAV_SUBJECTS[@]} CAV subjects (T1w + FLAIR)"
echo ""

# Create test patients directory
echo "Creating test_patients/ directory for pipeline testing..."
mkdir -p "${ROOT}/test_patients"

for subject_num in "${TEST_SUBJECTS[@]}"; do
    copy_subject_data "$subject_num" "${ROOT}/test_patients"
done

echo ""
echo "✓ Test patients/ directory created with ${#TEST_SUBJECTS[@]} subjects (T1w + FLAIR)"
echo ""

echo "=========================================="
echo "Setup complete!"
echo "=========================================="
echo ""
echo "Directory structure:"
echo "  patients/        - All ${#CAV_SUBJECTS[@]} CAV subjects (T1w + FLAIR)"
echo "  test_patients/   - ${#TEST_SUBJECTS[@]} subjects for quick testing"
echo ""
echo "Example folder structure:"
echo "  patients/sub-006_T1w/Input_NIfTI/sub-006_T1w.nii.gz"
echo "  patients/sub-006_FLAIR/Input_NIfTI/sub-006_FLAIR.nii.gz"
echo ""
echo "Next steps:"
echo "  1. Build Docker environment: docker-compose build"
echo "  2. Run preprocessing on test data first"
echo "  3. Then process full dataset"
