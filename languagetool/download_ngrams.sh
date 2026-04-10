#!/bin/bash
set -e

# Configuration
NGRAMS_URL="https://languagetool.org/download/ngram-data/ngrams-es-20150915.zip"
NGRAMS_DIR="./ngrams"
TEMP_ZIP="ngrams-es.zip"

echo "Checking for existing ngrams..."
if [ -d "$NGRAMS_DIR/es" ]; then
    echo "Spanish ngrams already exist in $NGRAMS_DIR/es. Skipping download."
    exit 0
fi

mkdir -p "$NGRAMS_DIR"

echo "Downloading Spanish ngrams from $NGRAMS_URL..."
curl -L -o "$TEMP_ZIP" "$NGRAMS_URL"

echo "Extracting ngrams..."
# Unzip to a temporary directory to inspect structure
TEMP_EXTRACT_DIR="temp_extract_ngrams"
mkdir -p "$TEMP_EXTRACT_DIR"
unzip -q "$TEMP_ZIP" -d "$TEMP_EXTRACT_DIR"

# Check if it extracted an 'es' directory or just files
if [ -d "$TEMP_EXTRACT_DIR/es" ]; then
    mv "$TEMP_EXTRACT_DIR/es" "$NGRAMS_DIR/"
elif [ -d "$TEMP_EXTRACT_DIR/ngrams-es-20150915" ]; then
     mv "$TEMP_EXTRACT_DIR/ngrams-es-20150915" "$NGRAMS_DIR/es"
else
    # Assume content is directly the ngrams if no directory matched perfectly,
    # but create 'es' directory to be safe and move contents there.
    # Actually, inspecting the usual structure, it often unzips to a folder with the zip name.
    # Let's handle the case where it's a folder named something else.
    # Find the single directory if it exists
    DIR_COUNT=$(find "$TEMP_EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
    if [ "$DIR_COUNT" -eq 1 ]; then
        SINGLE_DIR=$(find "$TEMP_EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d)
        mv "$SINGLE_DIR" "$NGRAMS_DIR/es"
    else
        # If multiple files/dirs, assume it's the content providing we should put it in 'es'
        mkdir -p "$NGRAMS_DIR/es"
        mv "$TEMP_EXTRACT_DIR"/* "$NGRAMS_DIR/es/"
    fi
fi

echo "Cleaning up..."
rm "$TEMP_ZIP"
rm -rf "$TEMP_EXTRACT_DIR"

echo "Done! Spanish ngrams installed to $NGRAMS_DIR/es"
