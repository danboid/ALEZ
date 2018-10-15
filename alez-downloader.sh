#!/bin/bash
# ALEZ downloader

# Remove and/or create temp dir for ALEZ repo
if [ ! -e /tmp/ALEZ ]; then
    mkdir /tmp/ALEZ
else
	rm -rf /tmp/ALEZ
	mkdir /tmp/ALEZ
fi

echo "Downloading ALEZ..."
git clone https://github.com/danboid/ALEZ.git /tmp/ALEZ
if [ "$?" == 0 ]; then
	echo "Running ALEZ"
	/bin/bash /tmp/ALEZ/alez.sh
	echo "Removing installer"
	rm -rf /tmp/ALEZ
else
	echo -e "\nFailed to download the ALEZ installer.\n\nPlease check your internet connection and try again."
	echo "Removing installer"
	rm -rf /tmp/ALEZ
fi
