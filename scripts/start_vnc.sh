#!/bin/bash
# Start VNC server inside Docker container for ITK-SNAP GUI access

# Kill any existing VNC servers
vncserver -kill :1 2>/dev/null || true

# Get VNC password if not set
if [ ! -f ~/.vnc/passwd ]; then
    echo "Please set a VNC password:"
    vncpasswd
    echo ""
fi

# Start VNC server
echo "Starting VNC server on display :1 (port 5901)..."
vncserver :1 -geometry 1920x1080 -depth 24 -localhost no

echo ""
echo "=========================================="
echo "VNC Server Started Successfully!"
echo "=========================================="
echo ""
echo "Connection details:"
echo "  Display: :1"
echo "  Port: 5901"
echo "  Password: (the one you just set)"
echo ""
echo "To connect from your local machine:"
echo "  1. Create SSH tunnel:"
echo "     ssh -L 5901:localhost:5901 ashwin@your-server"
echo ""
echo "  2. Use any VNC viewer to connect to:"
echo "     localhost:5901"
echo ""
echo "  3. VNC viewer options:"
echo "     - macOS: Built-in 'Screen Sharing' or TigerVNC Viewer"
echo "     - Windows: TigerVNC Viewer, RealVNC, TightVNC"
echo "     - Linux: Remmina, TigerVNC Viewer"
echo "     - VS Code: 'VNC Viewer for VS Code' extension"
echo ""
echo "To stop VNC server:"
echo "  vncserver -kill :1"
echo ""
echo "To access ITK-SNAP once connected:"
echo "  Open terminal in VNC session and run:"
echo "  itksnap /workspace/test_patients/sub-006_T1w/Output_Part1/sub-006_T1w_Step1_BFC.nii.gz"
echo "=========================================="
