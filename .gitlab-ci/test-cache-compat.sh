#!/bin/bash
# Copyright (C) 2026 fontconfig Authors
# SPDX-License-Identifier: HPND
#
# Cache compatibility test: builds a baseline fontconfig from a previous
# release tag and runs cross-version cache read/write tests.
#
# Environment:
#   FC_BASELINE_TAG  - Pin a specific baseline tag (e.g. "2.17.1").
#                      If empty, auto-detects the latest release tag
#                      with a lower cache version than current.
#   FDO_UPSTREAM_REPO - Upstream repo path (default: fontconfig/fontconfig)

set -e

upstream="https://gitlab.freedesktop.org/${FDO_UPSTREAM_REPO:-fontconfig/fontconfig}.git"

# Current build directory from parent artifacts
builddir=$(echo "$(pwd)"/build-fontconfig-*)

# Read current cache version from source meson.build (not the generated header)
current_cv=$(grep -m1 'cacheversion\s*=' meson.build | tr -dc '0-9')
echo ">>> Current cache version: $current_cv"

# Temporary bare repo for all git operations — avoids polluting
# the source tree with fetched tags/objects (important for local runs)
tmpgit=$(mktemp -d)
trap 'rm -rf "$tmpgit" "$baseline_src"' EXIT
git init --bare "$tmpgit" >/dev/null 2>&1

# --- Baseline tag selection ---
if [ -z "$FC_BASELINE_TAG" ]; then
    echo ">>> Auto-detecting baseline tag..."
    for tag in $(git ls-remote --tags --refs "$upstream" '2.*' \
                 | awk '{print $2}' | sed 's|refs/tags/||' | sort -Vr); do
        git -C "$tmpgit" fetch --depth=1 "$upstream" tag "$tag" \
            2>/dev/null || continue
        tag_cv=$(git -C "$tmpgit" show "$tag:meson.build" 2>/dev/null \
                 | grep -m1 'cacheversion\s*=' | tr -dc '0-9')
        [ -z "$tag_cv" ] && continue
        if [ "$tag_cv" -lt "$current_cv" ]; then
            FC_BASELINE_TAG="$tag"
            echo ">>> Selected baseline: $tag (cache version $tag_cv)"
            break
        fi
    done
    if [ -z "$FC_BASELINE_TAG" ]; then
        echo ">>> No older cache version found among release tags, skipping"
        exit 0
    fi
else
    echo ">>> Using pinned baseline: $FC_BASELINE_TAG"
    git -C "$tmpgit" fetch --depth=1 "$upstream" tag "$FC_BASELINE_TAG"
    tag_cv=$(git -C "$tmpgit" show "$FC_BASELINE_TAG:meson.build" 2>/dev/null \
             | grep -m1 'cacheversion\s*=' | tr -dc '0-9')
fi

# Extract baseline source from the temp repo
baseline_src=$(mktemp -d)
git -C "$tmpgit" archive "$FC_BASELINE_TAG" | tar -C "$baseline_src" -x

# Read baseline cache version from extracted source if not yet known
if [ -z "$tag_cv" ]; then
    tag_cv=$(grep -m1 'cacheversion\s*=' "$baseline_src/meson.build" | tr -dc '0-9')
fi
echo ">>> Baseline cache version: $tag_cv"

# Build baseline via build.py (current build infrastructure, old source)
echo ">>> Building baseline $FC_BASELINE_TAG..."
BUILDDIR="$baseline_src/build" \
PREFIX="$baseline_src/prefix" \
    python3 .gitlab-ci/build.py \
        --source-dir "$baseline_src" \
        -C -I \
        -d nls -d doc

# Activate venv (build.py creates it if missing; provides pytest, etc.)
if [ -f .venv/bin/activate ]; then
    . .venv/bin/activate
fi

# Run cross-version cache compatibility tests
echo ">>> Running cache compatibility tests..."
cd test
FC_BASELINE_BUILDDIR="$baseline_src/build" \
FC_BASELINE_CACHE_VERSION="$tag_cv" \
builddir="$builddir" \
srcdir="$(pwd)/.." \
    python3 -m pytest -v test_cache_cross_version.py \
        --tap --assert=plain
