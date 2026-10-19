#!/bin/sh
# Puts the language models the app bundles into ./Models (git-ignored).
#   scripts/fetch-models.sh                      download the pinned release (models.lock), verify SHA-256
#   scripts/fetch-models.sh --from <models-dir>  copy local models (e.g. ../../core/models after retraining)
set -eu
cd "$(dirname "$0")/.."
DEST=Models
FILES="lexicon.bin tagger.bin xpos.bin parser.bin inflect.bin lm.bin usage/usage.safetensors usage/usage.json usage/senses.bin usage/head/senses.safetensors usage/head/senses.json"

if [ "${1:-}" = "--from" ]; then
  SRC=${2:?usage: fetch-models.sh --from <models-dir>}
  rm -rf "$DEST" && mkdir -p "$DEST/usage/head"
  for f in $FILES; do cp "$SRC/$f" "$DEST/$f"; done
  echo "local" > "$DEST/.version"
  echo "Copied models from $SRC"
  exit 0
fi

# models.lock: VERSION, URL, SHA256 (one KEY=value per line)
. ./models.lock
if [ -f "$DEST/.version" ] && [ "$(cat "$DEST/.version")" = "$VERSION" ]; then
  echo "Models $VERSION already present"
  exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "Downloading models $VERSION"
curl -fsSL --retry 3 -o "$TMP/models.zip" "$URL"
ACTUAL=$(shasum -a 256 "$TMP/models.zip" | cut -d' ' -f1)
if [ "$ACTUAL" != "$SHA256" ]; then
  echo "error: models checksum mismatch (expected $SHA256, got $ACTUAL)" >&2
  exit 1
fi
rm -rf "$DEST" && mkdir -p "$DEST"
unzip -q "$TMP/models.zip" -d "$DEST"
for f in $FILES; do
  [ -f "$DEST/$f" ] || { echo "error: $f missing from models.zip" >&2; exit 1; }
done
echo "$VERSION" > "$DEST/.version"
echo "Models $VERSION ready in $DEST"
