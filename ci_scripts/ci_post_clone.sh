#!/bin/sh
# Xcode Cloud runs this after cloning: fetch the pinned language models so
# the "Bundle language models" build phase can include them.
set -eu
"$CI_PRIMARY_REPOSITORY_PATH/scripts/fetch-models.sh"
