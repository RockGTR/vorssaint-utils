#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Run in a full checkout of the personal branch. No push happens here: the
# workflow publishes this merge only after the build and tests pass.
set -euo pipefail
UPSTREAM_URL="${PERSONAL_UPSTREAM_URL:-https://github.com/vorssaint/vorssaint-utils.git}"
UPSTREAM_REF="${PERSONAL_UPSTREAM_REF:-main}"
git fetch --no-tags "$UPSTREAM_URL" "$UPSTREAM_REF"
UPSTREAM_SHA="$(git rev-parse FETCH_HEAD)"
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'

if ! git merge --no-edit "$UPSTREAM_SHA"; then
    CONFLICTS="$(git diff --name-only --diff-filter=U)"
    echo '::error title=Upstream merge failed::The personal changes could not be merged with upstream. Resolve the conflicts on the personal branch and rerun.'
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        {
            echo '### Upstream merge needs attention'
            echo "Upstream commit: $UPSTREAM_SHA"
            echo 'The previous release and remote personal branch are unchanged.'
            echo 'Conflicting files:'
            printf '\n```text\n%s\n```\n' "$CONFLICTS"
        } >> "$GITHUB_STEP_SUMMARY"
    fi
    printf '%s\n' "$CONFLICTS"
    git merge --abort || true
    exit 1
fi

SOURCE_SHA="$(git rev-parse HEAD)"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "source_sha=$SOURCE_SHA"
        echo "upstream_sha=$UPSTREAM_SHA"
    } >> "$GITHUB_OUTPUT"
fi
