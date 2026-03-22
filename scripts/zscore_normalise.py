#!/usr/bin/env python3
"""
Z-score intensity normalisation for skull-stripped brain MRI images.
Normalises brain voxel intensities to mean=0, std=1 using brain mask
derived from non-zero voxels after skull stripping, with lesion voxels
excluded from the mean and standard deviation calculation.
Saves the normalisation mask for visual quality control.

USAGE: python3 zscore_normalise.py <input_image> <output_image> <lesion_mask> <normalisation_mask_output>
"""

import sys
import numpy as np
import nibabel as nib

def zscore_normalise(input_path, output_path, lesion_mask_path, normalisation_mask_path):
    # Load the skull stripped image
    print(f"Loading image: {input_path}")
    img = nib.load(input_path)
    data = img.get_fdata()

    # Load the lesion mask (already in MNI space)
    print(f"Loading lesion mask: {lesion_mask_path}")
    lesion_img = nib.load(lesion_mask_path)
    lesion_data = lesion_img.get_fdata()

    # Create brain mask from non-zero voxels after skull stripping
    brain_mask = data > 0

    # Create normalisation mask: brain voxels excluding lesion voxels
    lesion_mask = lesion_data > 0
    normalisation_mask = brain_mask & ~lesion_mask

    # Check that the normalisation mask is not empty
    if not np.any(normalisation_mask):
        print("ERROR: Normalisation mask is empty — check that skull stripping and lesion mask are valid")
        sys.exit(1)

    # Save the normalisation mask for visual quality control
    normalisation_img = nib.Nifti1Image(normalisation_mask.astype(np.float32), img.affine, img.header)
    nib.save(normalisation_img, normalisation_mask_path)
    print(f"Normalisation mask saved to: {normalisation_mask_path}")

    # Calculate mean and standard deviation from normal brain voxels only
    brain_mean = np.mean(data[normalisation_mask])
    brain_std = np.std(data[normalisation_mask])

    print(f"Brain mean intensity (lesion excluded): {brain_mean:.4f}")
    print(f"Brain std intensity  (lesion excluded): {brain_std:.4f}")

    # Check that standard deviation is not zero
    if brain_std == 0:
        print("ERROR: Brain standard deviation is zero — cannot normalise")
        sys.exit(1)

    # Apply z-score normalisation to brain voxels only
    # Initialise output as zeros so background remains exactly zero
    # The formula is anchored to normal brain tissue statistics
    normalised_data = np.zeros_like(data)
    normalised_data[brain_mask] = (data[brain_mask] - brain_mean) / brain_std

    # Save the normalised image preserving the original header and affine
    normalised_img = nib.Nifti1Image(normalised_data.astype(np.float32), img.affine, img.header)
    nib.save(normalised_img, output_path)
    print(f"Normalised image saved to: {output_path}")

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("USAGE: python3 zscore_normalise.py <input_image> <output_image> <lesion_mask> <normalisation_mask_output>")
        sys.exit(1)
    zscore_normalise(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
