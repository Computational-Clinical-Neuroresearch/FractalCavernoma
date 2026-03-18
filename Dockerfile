# Dockerfile for Fractal Cavernoma MRI Preprocessing Pipeline
# GPU-accelerated neuroimaging pipeline with FSL, ANTs, HD-BET, and ITK-SNAP

FROM nvidia/cuda:12.2.0-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHON_VERSION=3.10

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget curl git build-essential cmake \
    python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python3-pip python${PYTHON_VERSION}-dev \
    zlib1g-dev libgl1-mesa-glx libglib2.0-0 libsm6 libxext6 libxrender-dev \
    libgomp1 dc bc libopenblas-dev liblapack-dev \
    tigervnc-standalone-server tigervnc-common xfce4 xfce4-goodies \
    dbus-x11 x11-xserver-utils \
    && rm -rf /var/lib/apt/lists/*

# Create Python virtual environment
RUN python${PYTHON_VERSION} -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python packages with GPU support
# Use PyTorch 2.0.1 for HD-BET compatibility (GradScaler location)
RUN pip install --upgrade pip wheel setuptools && \
    pip install \
    torch==2.0.1 torchvision==0.15.2 \
    --index-url https://download.pytorch.org/whl/cu118 && \
    pip install \
    nibabel==5.2.0 numpy==1.26.3 scipy==1.11.4 \
    pandas==2.1.4 scikit-learn==1.3.2 matplotlib==3.8.2 \
    SimpleITK==2.3.1 nilearn==0.10.3 HD-BET pywavelets six opencv-python-headless imea && \
    pip install --no-build-isolation pyradiomics==3.0.1

# Install ANTs (Advanced Normalization Tools)
# Note: HD-BET models will auto-download on first use
WORKDIR /opt
RUN git clone --depth 1 --branch v2.5.0 https://github.com/ANTsX/ANTs.git && \
    cd ANTs && mkdir build && cd build && \
    cmake .. && make -j$(nproc) && \
    mkdir -p /opt/ants/bin && \
    cp -r bin/* /opt/ants/bin/ 2>/dev/null || \
    find . -type f -executable ! -name "*.so*" -exec cp {} /opt/ants/bin/ \; && \
    cd /opt && rm -rf ANTs

# Download MNI152 template from MNI directly
RUN mkdir -p /opt/fsl/data/standard /tmp/mni && \
    wget -q -O /tmp/mni.zip \
    https://www.bic.mni.mcgill.ca/~vfonov/icbm/2009/mni_icbm152_nlin_sym_09a_nifti.zip && \
    apt-get update && apt-get install -y unzip && \
    unzip -j /tmp/mni.zip "mni_icbm152_nlin_sym_09a/mni_icbm152_t1_tal_nlin_sym_09a.nii" -d /opt/fsl/data/standard/ && \
    gzip /opt/fsl/data/standard/mni_icbm152_t1_tal_nlin_sym_09a.nii && \
    mv /opt/fsl/data/standard/mni_icbm152_t1_tal_nlin_sym_09a.nii.gz /opt/fsl/data/standard/MNI152_T1_1mm.nii.gz && \
    rm -rf /tmp/mni.zip /tmp/mni && \
    rm -rf /var/lib/apt/lists/*

# Set all environment variables at once (order matters!)
ENV ANTSPATH="/opt/ants/bin" \
    FSLDIR="/opt/fsl" \
    FSLOUTPUTTYPE="NIFTI_GZ" \
    PATH="/opt/ants/bin:/opt/venv/bin:/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Configure VNC
RUN mkdir -p /root/.vnc && \
    echo '#!/bin/bash\nunset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS\nstartxfce4 &' > /root/.vnc/xstartup && \
    chmod +x /root/.vnc/xstartup

WORKDIR /workspace
EXPOSE 5901

CMD ["/bin/bash"]
