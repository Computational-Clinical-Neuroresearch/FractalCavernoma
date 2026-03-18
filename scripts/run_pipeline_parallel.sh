#!/usr/bin/env bash
set -euo pipefail

# Parallel MRI preprocessing pipeline with GPU load balancing
# Uses GNU parallel to distribute jobs across GPUs 0 and 1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Default to patients directory
PATIENTS_DIR="${1:-patients}"
PART="${2:-both}"  # Options: part1, part2, both

# Check if GNU parallel is installed
if ! command -v parallel >/dev/null 2>&1; then
    echo "ERROR: GNU parallel not found. Installing..."
    apt-get update && apt-get install -y parallel
fi

# Get list of subjects
SUBJECTS=($(ls -d ${PATIENTS_DIR}/sub-*/ | xargs -n1 basename))
NUM_SUBJECTS=${#SUBJECTS[@]}

echo "=========================================="
echo "Parallel MRI Preprocessing Pipeline"
echo "=========================================="
echo "Directory: ${PATIENTS_DIR}"
echo "Subjects: ${NUM_SUBJECTS}"
echo "GPUs: 0, 1"
echo "Part: ${PART}"
echo "=========================================="
echo ""

# Function to run Part 1 on a subject with specific GPU
run_part1() {
    local subject="$1"
    local gpu_id="$2"
    local patients_dir="$3"

    echo "[GPU ${gpu_id}] Starting Part 1 for ${subject}..."

    # Export GPU for this process
    export CUDA_VISIBLE_DEVICES=${gpu_id}

    # Run preprocessing
    cd "$ROOT/scripts"
    ./mri_preprocess_part1.sh "${subject}" "${patients_dir}" 2>&1 | \
        sed "s/^/[GPU ${gpu_id}] [${subject}] /"

    echo "[GPU ${gpu_id}] Completed Part 1 for ${subject}"
}

# Function to run Part 2 on a subject with specific GPU
run_part2() {
    local subject="$1"
    local gpu_id="$2"
    local patients_dir="$3"

    echo "[GPU ${gpu_id}] Starting Part 2 for ${subject}..."

    # Export GPU for this process
    export CUDA_VISIBLE_DEVICES=${gpu_id}

    # Run preprocessing
    cd "$ROOT/scripts"
    ./mri_preprocess_part2.sh "${subject}" "${patients_dir}" 2>&1 | \
        sed "s/^/[GPU ${gpu_id}] [${subject}] /"

    echo "[GPU ${gpu_id}] Completed Part 2 for ${subject}"
}

# Export functions for parallel
export -f run_part1
export -f run_part2
export ROOT

# Part 1: Bias field correction (CPU-only, run 4 at a time)
if [ "$PART" = "part1" ] || [ "$PART" = "both" ]; then
    echo "Running Part 1: Bias field correction..."
    echo ""

    # Run 4 subjects in parallel (Part 1 doesn't use GPU heavily)
    parallel -j 4 --bar --joblog "${PATIENTS_DIR}_part1.log" \
        'run_part1 {} $(( {%} % 2 )) '"${PATIENTS_DIR}" ::: "${SUBJECTS[@]}"

    echo ""
    echo "Part 1 complete!"
    echo ""

    if [ "$PART" = "part1" ]; then
        echo "=========================================="
        echo "NEXT STEP: Manual lesion segmentation"
        echo "Open each subject's bias-corrected image in ITK-SNAP"
        echo "Draw lesion mask and save to Lesion_Mask/ folder"
        echo "Then run: ./run_pipeline_parallel.sh ${PATIENTS_DIR} part2"
        echo "=========================================="
        exit 0
    fi

    echo "Waiting for manual lesion segmentation..."
    echo "Press ENTER when all lesion masks are ready, or Ctrl+C to exit"
    read -r
fi

# Part 2: Registration, skull stripping (GPU-accelerated), normalization
# Run 2 at a time (one per GPU)
if [ "$PART" = "part2" ] || [ "$PART" = "both" ]; then
    echo "Running Part 2: Registration, skull stripping, normalization..."
    echo ""

    # Check that lesion masks exist
    MISSING_MASKS=()
    for subject in "${SUBJECTS[@]}"; do
        MASK="${PATIENTS_DIR}/${subject}/Lesion_Mask/${subject}_lesion_mask.nii.gz"
        if [ ! -f "$MASK" ]; then
            MISSING_MASKS+=("$subject")
        fi
    done

    if [ ${#MISSING_MASKS[@]} -gt 0 ]; then
        echo "ERROR: Missing lesion masks for the following subjects:"
        printf '  - %s\n' "${MISSING_MASKS[@]}"
        echo ""
        echo "Please complete manual segmentation for all subjects before running Part 2"
        exit 1
    fi

    # Run 2 subjects in parallel (one per GPU for GPU-intensive HD-BET)
    parallel -j 2 --bar --joblog "${PATIENTS_DIR}_part2.log" \
        'run_part2 {} $(( {%} % 2 )) '"${PATIENTS_DIR}" ::: "${SUBJECTS[@]}"

    echo ""
    echo "Part 2 complete!"
    echo ""
fi

echo "=========================================="
echo "Pipeline complete!"
echo "=========================================="
echo ""
echo "Preprocessed data location:"
echo "  ${PATIENTS_DIR}/*/Output_Part2/*_Step4_ZScore.nii.gz"
echo ""
echo "Next steps:"
echo "  1. Radiomics feature extraction"
echo "  2. Fractal dimension analysis"
echo "  3. Statistical analysis"
echo ""
echo "Job logs:"
if [ -f "${PATIENTS_DIR}_part1.log" ]; then
    echo "  Part 1: ${PATIENTS_DIR}_part1.log"
fi
if [ -f "${PATIENTS_DIR}_part2.log" ]; then
    echo "  Part 2: ${PATIENTS_DIR}_part2.log"
fi
echo "=========================================="
