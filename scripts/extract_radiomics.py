#!/usr/bin/env python3
"""
Radiomics feature extraction for cavernous malformation analysis.

Extracts shape, intensity, and texture features from lesion ROIs using PyRadiomics.
Features are extracted from z-score normalized, MNI-registered brain images.

Usage:
    python extract_radiomics.py <patients_dir> <output_csv>

Example:
    python extract_radiomics.py test_patients radiomics_features.csv
"""

import sys
import os
from pathlib import Path
import pandas as pd
import numpy as np
from radiomics import featureextractor
import SimpleITK as sitk
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='[%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)


def setup_feature_extractor():
    """
    Configure PyRadiomics feature extractor.

    Returns:
        featureextractor.RadiomicsFeatureExtractor: Configured extractor
    """
    # Radiomics settings
    settings = {
        'binWidth': 0.25,  # Fixed bin width for z-scored images
        'interpolator': sitk.sitkBSpline,
        'resampledPixelSpacing': None,  # Use original spacing (already in MNI)
        'normalize': False,  # Already z-score normalized
        'normalizeScale': 1,
        'removeOutliers': None,
        'voxelArrayShift': 0,
        'label': 1  # Lesion mask label value
    }

    # Initialize extractor with all feature classes enabled
    extractor = featureextractor.RadiomicsFeatureExtractor(**settings)

    # Enable all feature classes
    extractor.enableAllImageTypes()  # Original images only (no filters)
    extractor.enableAllFeatures()    # All feature classes

    logger.info("Feature extractor configured:")
    logger.info(f"  Bin width: {settings['binWidth']}")
    logger.info(f"  Image types: Original")
    logger.info(f"  Feature classes: All (shape, firstorder, glcm, glrlm, glszm, gldm, ngtdm)")

    return extractor


def extract_features_for_subject(extractor, subject_path):
    """
    Extract radiomics features for a single subject.

    Args:
        extractor: Configured PyRadiomics feature extractor
        subject_path: Path to subject directory (e.g., test_patients/sub-6_T1w)

    Returns:
        dict: Feature dictionary with metadata
    """
    subject_id = subject_path.name
    output_dir = subject_path / "Output_Part2"

    # Find preprocessed image and lesion mask
    image_path = output_dir / f"{subject_id}_Step4_ZScore.nii.gz"
    mask_path = output_dir / f"{subject_id}_lesion_mask_MNI.nii.gz"

    # Validate files exist
    if not image_path.exists():
        logger.warning(f"  Skipping {subject_id}: Missing preprocessed image")
        return None

    if not mask_path.exists():
        logger.warning(f"  Skipping {subject_id}: Missing lesion mask")
        return None

    # Extract features
    logger.info(f"  Extracting features for {subject_id}...")
    try:
        result = extractor.execute(str(image_path), str(mask_path))

        # Convert to dictionary, removing diagnostics
        features = {}
        for key, value in result.items():
            # Skip diagnostic features
            if key.startswith('diagnostics_'):
                continue

            # Convert numpy types to Python natives for CSV export
            if isinstance(value, np.ndarray):
                value = value.item()
            elif isinstance(value, (np.integer, np.floating)):
                value = value.item()

            features[key] = value

        # Add metadata
        sequence_type = 'T1w' if 'T1w' in subject_id else 'FLAIR'
        subject_num = subject_id.split('_')[0]  # e.g., "sub-6"

        features['subject_id'] = subject_id
        features['subject_num'] = subject_num
        features['sequence'] = sequence_type

        logger.info(f"  ✓ Extracted {len(features)-3} features for {subject_id}")
        return features

    except Exception as e:
        logger.error(f"  ✗ Failed to extract features for {subject_id}: {e}")
        return None


def main():
    """Main radiomics extraction pipeline."""

    # Parse arguments
    if len(sys.argv) != 3:
        print("Usage: python extract_radiomics.py <patients_dir> <output_csv>")
        print("Example: python extract_radiomics.py test_patients radiomics_features.csv")
        sys.exit(1)

    patients_dir = Path(sys.argv[1])
    output_csv = Path(sys.argv[2])

    # Validate patients directory
    if not patients_dir.exists():
        logger.error(f"Patients directory not found: {patients_dir}")
        sys.exit(1)

    # Find all subject directories
    subject_dirs = sorted(patients_dir.glob("sub-*"))
    if not subject_dirs:
        logger.error(f"No subject directories found in {patients_dir}")
        sys.exit(1)

    logger.info("="*60)
    logger.info("Radiomics Feature Extraction Pipeline")
    logger.info("="*60)
    logger.info(f"Patients directory: {patients_dir}")
    logger.info(f"Output CSV: {output_csv}")
    logger.info(f"Subjects found: {len(subject_dirs)}")
    logger.info("")

    # Setup feature extractor
    extractor = setup_feature_extractor()
    logger.info("")

    # Extract features for all subjects
    all_features = []
    for subject_path in subject_dirs:
        features = extract_features_for_subject(extractor, subject_path)
        if features:
            all_features.append(features)

    # Convert to DataFrame
    if not all_features:
        logger.error("No features extracted. Check your data.")
        sys.exit(1)

    df = pd.DataFrame(all_features)

    # Reorder columns: metadata first, then features
    metadata_cols = ['subject_id', 'subject_num', 'sequence']
    feature_cols = [col for col in df.columns if col not in metadata_cols]
    df = df[metadata_cols + sorted(feature_cols)]

    # Save to CSV
    df.to_csv(output_csv, index=False)

    logger.info("")
    logger.info("="*60)
    logger.info(f"✓ Feature extraction complete!")
    logger.info(f"  Subjects processed: {len(all_features)}/{len(subject_dirs)}")
    logger.info(f"  Features per subject: {len(feature_cols)}")
    logger.info(f"  Output saved to: {output_csv}")
    logger.info("="*60)

    # Print feature summary
    logger.info("")
    logger.info("Feature summary:")

    # Group features by class
    feature_classes = {}
    for col in feature_cols:
        # Parse feature name: original_firstorder_Mean -> firstorder
        parts = col.split('_')
        if len(parts) >= 2:
            class_name = parts[1] if parts[0] == 'original' else parts[0]
            feature_classes[class_name] = feature_classes.get(class_name, 0) + 1

    for class_name, count in sorted(feature_classes.items()):
        logger.info(f"  {class_name}: {count} features")

    logger.info("")
    logger.info("Next steps:")
    logger.info("  1. Review radiomics_features.csv")
    logger.info("  2. Perform feature selection (correlation, variance)")
    logger.info("  3. Statistical analysis / Machine learning")


if __name__ == "__main__":
    main()
