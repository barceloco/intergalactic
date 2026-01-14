#!/bin/bash
# Inspect the lego Docker image to see what /lego is

echo "Inspecting lego image structure..."
echo ""

# Check if /lego exists in the image and what it is
docker run --rm --entrypoint sh goacme/lego:v4.14.2 -c "
    echo 'Checking /lego:'
    ls -ld /lego 2>&1 || echo '/lego does not exist'
    echo ''
    echo 'Checking if /lego is a file or directory:'
    [ -d /lego ] && echo '/lego is a directory' || echo '/lego is NOT a directory'
    [ -f /lego ] && echo '/lego is a file' || echo '/lego is NOT a file'
    echo ''
    echo 'Contents of / (root):'
    ls -la / | grep -E '^d|^\-' | head -20
    echo ''
    echo 'Checking for any existing /lego:'
    find / -maxdepth 2 -name lego 2>/dev/null | head -10
"

echo ""
echo "Checking image layers for /lego..."
docker history goacme/lego:v4.14.2 | head -10
