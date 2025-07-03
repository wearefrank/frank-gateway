#!/bin/bash

# Copy mounted project files (optional)
if [ -d "$MOUNTED_PROJECT_DIR" ]; then
  cp -a $MOUNTED_PROJECT_DIR/. $PROJECT_DIR
fi

# Copy any external JARs
if [ -d "$MOUNTED_EXT_DIR" ]; then
  cp -a $MOUNTED_EXT_DIR/. $SOAPUI_DIR/bin/ext
fi

# Run project
./RunProject.sh
EXIT_CODE=$?

# Custom exit codes for SoapUI
if [ $EXIT_CODE -eq 1 ]; then
  exit 102
elif [ $EXIT_CODE -ne 0 ]; then
  exit 103
else
  exit 0
fi
