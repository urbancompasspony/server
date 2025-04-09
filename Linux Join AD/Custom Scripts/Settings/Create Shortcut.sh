
sudo chmod +x /etc/profile.d/create_shortcut.sh

#!/bin/bash

# Define the mount folder path
MOUNT_POINT="/mnt/DAT"

# Define the shortcut location
SHORTCUT_PATH="$HOME/Desktop/DAT.desktop"

# Check if the folder is mounted
if mount | grep -q "$MOUNT_POINT"; then
    # If mounted, create the shortcut
    echo "[Desktop Entry]
Type=Link
Name=DAT Shared Folder
Icon=folder
URL=file://$MOUNT_POINT" > "$SHORTCUT_PATH"

    # Make it executable
    chmod +x "$SHORTCUT_PATH"
else
    # If not mounted, remove the shortcut
    if [ -f "$SHORTCUT_PATH" ]; then
        rm "$SHORTCUT_PATH"
    fi
fi
