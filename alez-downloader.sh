#!/bin/bash
# ALEZ downloader

# Exit on error
set -o errexit -o errtrace

alez_dir="/usr/local/share/ALEZ"

# Check repo exists, if it does pull updates
pull_updates() {    
    if [ -d "${alez_dir}/.git" ]; then
        echo "Updating ALEZ..."
        pushd "${alez_dir}"
        git fetch --depth 1
        git reset --hard origin/master
        popd
    else
        echo "Downloading ALEZ..."
        mkdir -p "${alez_dir}"
        if ! git clone --branch master --single-branch --depth 1 \
            https://github.com/danboid/ALEZ.git "${alez_dir}"; then
            printf "\n%s\n\n%s" "Failed to download the ALEZ installer." \
                          "Please check your internet connection and try again."
        fi
    fi
}

pull_updates

echo "Running ALEZ"
/bin/bash "${alez_dir}/alez.sh"
