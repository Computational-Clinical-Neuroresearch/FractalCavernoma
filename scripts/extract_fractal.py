#!/usr/bin/env python3
"""
3D Fractal Dimension and Lacunarity extraction for cavernous malformations.

Adapted from: https://github.com/nibr-lab/Fractal-Dimension-and-Lacunarity-in-Gliomas
Methods based on:
- Fractal Dimension: Box-counting algorithm
- Lacunarity: Gliding-box algorithm

Computes metrics across all 3 anatomical planes (axial, coronal, sagittal).

Usage:
    python extract_fractal.py <patients_dir> <output_csv>

Example:
    python extract_fractal.py test_patients fractal_features.csv
"""

import sys
import os
from pathlib import Path
import pandas as pd
import numpy as np
import nibabel as nb
import cv2
from scipy.signal import convolve2d as conv2d
import logging

# Import imea for fractal dimension calculation
try:
    from imea.measure_2d.micro import fractal_dimension_boxcounting as fract_dim
except ImportError:
    print("ERROR: imea package not found. Install with: pip install imea")
    sys.exit(1)

# Configure logging
logging.basicConfig(level=logging.INFO, format='[%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)


def fractal_dimension_2d(slice_data):
    """
    Calculate fractal dimension of a single 2D slice using box-counting.

    Args:
        slice_data: 2D numpy array (binary mask, 0 or 1)

    Returns:
        float: Fractal dimension (typically 1.0 - 2.0)
    """
    slice_data = slice_data.astype(np.uint8)

    # Find bounding box of lesion
    bin_ = np.zeros(slice_data.shape)
    bin_[slice_data != 0] = 1
    bin_ = bin_.astype(np.uint8)

    contours = cv2.findContours(image=bin_, mode=cv2.RETR_TREE, method=cv2.CHAIN_APPROX_SIMPLE)[0]

    if len(contours) == 0:
        return 0.0

    contours = sorted(contours, key=cv2.contourArea, reverse=True)
    c_0 = contours[0]
    xx, yy, w, h = cv2.boundingRect(c_0)

    # Crop to bounding box
    cropped = slice_data[yy:yy+h, xx:xx+w]

    # Binarize
    binary = np.zeros(cropped.shape)
    binary[cropped != 0] = 1

    # Calculate FD
    fd = fract_dim(binary)

    return fd


def lacunarity_2d(slice_data):
    """
    Calculate lacunarity of a single 2D slice using gliding-box algorithm.

    Args:
        slice_data: 2D numpy array (binary mask, 0 or 1)

    Returns:
        float: Lacunarity value
    """
    slice_data = slice_data.astype(np.uint8)

    # Find bounding box
    bin_ = np.zeros(slice_data.shape)
    bin_[slice_data != 0] = 1
    bin_ = bin_.astype(np.uint8)

    contours = cv2.findContours(image=bin_, mode=cv2.RETR_TREE, method=cv2.CHAIN_APPROX_SIMPLE)[0]

    if len(contours) == 0:
        return 0.0

    contours = sorted(contours, key=cv2.contourArea, reverse=True)
    c_0 = contours[0]
    xx, yy, w, h = cv2.boundingRect(c_0)

    # Crop to bounding box
    X = slice_data[yy:yy+h, xx:xx+w]

    # Define box sizes (up to 45% of ROI area)
    box_sizes = [i for i in range(2, 240)
                 if (i**2 < 0.45 * X.shape[0] * X.shape[1])
                 and i <= min(X.shape[0], X.shape[1])]

    if len(box_sizes) == 0:
        return 0.0

    # Binarize
    XX = np.zeros(X.shape)
    XX[X != 0] = 1

    LAMBDA = []

    for box in box_sizes:
        # Gliding box convolution
        count, edge = np.histogram(
            np.ravel(conv2d(XX, np.ones((box, box)), mode='valid')),
            bins=[i for i in range(0, box**2 + 2)]
        )

        # Probability distribution
        q = count / (XX.shape[0] - box + 1)**2
        s = np.array([i for i in range(0, box**2 + 1)])

        # Lacunarity = variance / mean^2
        denominator = sum(q * s)
        if denominator > 0:
            lam_bda = sum((s**2) * q) / (denominator**2)
            LAMBDA.append(lam_bda)

    return np.nanmean(LAMBDA) if len(LAMBDA) > 0 else 0.0


def compute_3d_fd(mask_data):
    """
    Compute 3D fractal dimension across all three planes.

    Args:
        mask_data: 3D numpy array (lesion mask in MNI space)

    Returns:
        dict: FD metrics for axial, coronal, sagittal, and 3D mean
    """
    mask_data = mask_data.astype(np.uint8)

    # Axial plane (slice along z-axis)
    mask_axial = np.delete(mask_data,
                           [i for i in range(mask_data.shape[2])
                            if np.sum(mask_data[:, :, i]) < 10],
                           axis=2)
    slices_axial = [mask_axial[:, :, i] for i in range(mask_axial.shape[2])]
    fd_axial = np.array([fractal_dimension_2d(s) for s in slices_axial])
    fd_axial = fd_axial[fd_axial > 0]  # Remove empty slices

    # Coronal plane (slice along y-axis)
    mask_coronal = np.delete(mask_data,
                             [i for i in range(mask_data.shape[1])
                              if np.sum(mask_data[:, i, :]) < 10],
                             axis=1)
    slices_coronal = [mask_coronal[:, i, :] for i in range(mask_coronal.shape[1])]
    fd_coronal = np.array([fractal_dimension_2d(s) for s in slices_coronal])
    fd_coronal = fd_coronal[fd_coronal > 0]

    # Sagittal plane (slice along x-axis)
    mask_sagittal = np.delete(mask_data,
                              [i for i in range(mask_data.shape[0])
                               if np.sum(mask_data[i, :, :]) < 10],
                              axis=0)
    slices_sagittal = [mask_sagittal[i, :, :] for i in range(mask_sagittal.shape[0])]
    fd_sagittal = np.array([fractal_dimension_2d(s) for s in slices_sagittal])
    fd_sagittal = fd_sagittal[fd_sagittal > 0]

    # Compute statistics
    results = {
        'fd_axial_mean': np.mean(fd_axial) if len(fd_axial) > 0 else 0,
        'fd_axial_median': np.median(fd_axial) if len(fd_axial) > 0 else 0,
        'fd_coronal_mean': np.mean(fd_coronal) if len(fd_coronal) > 0 else 0,
        'fd_coronal_median': np.median(fd_coronal) if len(fd_coronal) > 0 else 0,
        'fd_sagittal_mean': np.mean(fd_sagittal) if len(fd_sagittal) > 0 else 0,
        'fd_sagittal_median': np.median(fd_sagittal) if len(fd_sagittal) > 0 else 0,
    }

    # 3D FD = average across all planes
    results['fd_3d_mean'] = np.mean([
        results['fd_axial_mean'],
        results['fd_coronal_mean'],
        results['fd_sagittal_mean']
    ])

    results['fd_3d_median'] = np.mean([
        results['fd_axial_median'],
        results['fd_coronal_median'],
        results['fd_sagittal_median']
    ])

    return results


def compute_3d_lacunarity(mask_data):
    """
    Compute 3D lacunarity across all three planes.

    Args:
        mask_data: 3D numpy array (lesion mask in MNI space)

    Returns:
        dict: Lacunarity metrics for axial, coronal, sagittal, and 3D mean
    """
    mask_data = mask_data.astype(np.uint8)

    # Axial plane
    mask_axial = np.delete(mask_data,
                           [i for i in range(mask_data.shape[2])
                            if np.sum(mask_data[:, :, i]) < 10],
                           axis=2)
    slices_axial = [mask_axial[:, :, i] for i in range(mask_axial.shape[2])]
    lac_axial = np.array([lacunarity_2d(s) for s in slices_axial])
    lac_axial = lac_axial[lac_axial > 0]

    # Coronal plane
    mask_coronal = np.delete(mask_data,
                             [i for i in range(mask_data.shape[1])
                              if np.sum(mask_data[:, i, :]) < 10],
                             axis=1)
    slices_coronal = [mask_coronal[:, i, :] for i in range(mask_coronal.shape[1])]
    lac_coronal = np.array([lacunarity_2d(s) for s in slices_coronal])
    lac_coronal = lac_coronal[lac_coronal > 0]

    # Sagittal plane
    mask_sagittal = np.delete(mask_data,
                              [i for i in range(mask_data.shape[0])
                               if np.sum(mask_data[i, :, :]) < 10],
                              axis=0)
    slices_sagittal = [mask_sagittal[i, :, :] for i in range(mask_sagittal.shape[0])]
    lac_sagittal = np.array([lacunarity_2d(s) for s in slices_sagittal])
    lac_sagittal = lac_sagittal[lac_sagittal > 0]

    # Compute statistics
    results = {
        'lac_axial_mean': np.nanmean(lac_axial) if len(lac_axial) > 0 else 0,
        'lac_axial_median': np.nanmedian(lac_axial) if len(lac_axial) > 0 else 0,
        'lac_coronal_mean': np.nanmean(lac_coronal) if len(lac_coronal) > 0 else 0,
        'lac_coronal_median': np.nanmedian(lac_coronal) if len(lac_coronal) > 0 else 0,
        'lac_sagittal_mean': np.nanmean(lac_sagittal) if len(lac_sagittal) > 0 else 0,
        'lac_sagittal_median': np.nanmedian(lac_sagittal) if len(lac_sagittal) > 0 else 0,
    }

    # 3D lacunarity = average across all planes
    results['lac_3d_mean'] = np.nanmean([
        results['lac_axial_mean'],
        results['lac_coronal_mean'],
        results['lac_sagittal_mean']
    ])

    results['lac_3d_median'] = np.nanmean([
        results['lac_axial_median'],
        results['lac_coronal_median'],
        results['lac_sagittal_median']
    ])

    return results


def extract_fractal_for_subject(subject_path):
    """
    Extract fractal metrics for a single subject.

    Args:
        subject_path: Path to subject directory

    Returns:
        dict: Fractal features with metadata
    """
    subject_id = subject_path.name
    output_dir = subject_path / "Output_Part2"

    # Load lesion mask in MNI space
    mask_path = output_dir / f"{subject_id}_lesion_mask_MNI.nii.gz"

    if not mask_path.exists():
        logger.warning(f"  Skipping {subject_id}: Missing lesion mask in MNI space")
        return None

    logger.info(f"  Extracting fractal metrics for {subject_id}...")

    try:
        # Load mask
        mask_img = nb.load(str(mask_path))
        mask_data = mask_img.get_fdata()

        # Binarize (ensure mask is 0/1)
        mask_data = (mask_data > 0).astype(np.uint8)

        # Compute 3D FD
        fd_metrics = compute_3d_fd(mask_data)

        # Compute 3D Lacunarity
        lac_metrics = compute_3d_lacunarity(mask_data)

        # Combine results
        features = {**fd_metrics, **lac_metrics}

        # Add metadata
        sequence_type = 'T1w' if 'T1w' in subject_id else 'FLAIR'
        subject_num = subject_id.split('_')[0]

        features['subject_id'] = subject_id
        features['subject_num'] = subject_num
        features['sequence'] = sequence_type

        logger.info(f"  ✓ Extracted fractal metrics for {subject_id}")
        logger.info(f"    3D FD = {features['fd_3d_mean']:.4f}, 3D Lac = {features['lac_3d_mean']:.4f}")

        return features

    except Exception as e:
        logger.error(f"  ✗ Failed to extract fractal metrics for {subject_id}: {e}")
        return None


def main():
    """Main fractal extraction pipeline."""

    if len(sys.argv) != 3:
        print("Usage: python extract_fractal.py <patients_dir> <output_csv>")
        print("Example: python extract_fractal.py test_patients fractal_features.csv")
        sys.exit(1)

    patients_dir = Path(sys.argv[1])
    output_csv = Path(sys.argv[2])

    if not patients_dir.exists():
        logger.error(f"Patients directory not found: {patients_dir}")
        sys.exit(1)

    # Find all subject directories
    subject_dirs = sorted(patients_dir.glob("sub-*"))
    if not subject_dirs:
        logger.error(f"No subject directories found in {patients_dir}")
        sys.exit(1)

    logger.info("="*60)
    logger.info("3D Fractal Dimension and Lacunarity Extraction")
    logger.info("="*60)
    logger.info(f"Patients directory: {patients_dir}")
    logger.info(f"Output CSV: {output_csv}")
    logger.info(f"Subjects found: {len(subject_dirs)}")
    logger.info("")
    logger.info("Methods:")
    logger.info("  - Fractal Dimension: Box-counting algorithm")
    logger.info("  - Lacunarity: Gliding-box algorithm")
    logger.info("  - Computed across: Axial, Coronal, Sagittal planes")
    logger.info("")

    # Extract features for all subjects
    all_features = []
    for subject_path in subject_dirs:
        features = extract_fractal_for_subject(subject_path)
        if features:
            all_features.append(features)

    if not all_features:
        logger.error("No features extracted. Check your data.")
        sys.exit(1)

    # Convert to DataFrame
    df = pd.DataFrame(all_features)

    # Reorder columns: metadata first, then features
    metadata_cols = ['subject_id', 'subject_num', 'sequence']
    feature_cols = [col for col in df.columns if col not in metadata_cols]
    df = df[metadata_cols + sorted(feature_cols)]

    # Save to CSV
    df.to_csv(output_csv, index=False)

    logger.info("")
    logger.info("="*60)
    logger.info(f"✓ Fractal extraction complete!")
    logger.info(f"  Subjects processed: {len(all_features)}/{len(subject_dirs)}")
    logger.info(f"  Features per subject: {len(feature_cols)}")
    logger.info(f"  Output saved to: {output_csv}")
    logger.info("="*60)

    # Print feature summary
    logger.info("")
    logger.info("Feature summary:")
    logger.info(f"  Fractal Dimension metrics: 8")
    logger.info(f"    - Axial: mean, median")
    logger.info(f"    - Coronal: mean, median")
    logger.info(f"    - Sagittal: mean, median")
    logger.info(f"    - 3D: mean, median")
    logger.info(f"  Lacunarity metrics: 8")
    logger.info(f"    - Axial: mean, median")
    logger.info(f"    - Coronal: mean, median")
    logger.info(f"    - Sagittal: mean, median")
    logger.info(f"    - 3D: mean, median")


if __name__ == "__main__":
    main()
