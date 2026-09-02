#!/usr/bin/env bash
#
# Merge the latest upstream release tag into the tip of the tracked GUI3 branch
# and record the result as a patch under patches/.
#
# The RPM needs both halves of upstream: the version from the newest release and
# the front-end work that only exists on the feature branch. Neither branch has
# both, and a merge commit would have to be fetchable by COPR at build time --
# which would mean pushing to a fork of lemonade. Instead the submodule stays
# pinned to upstream's own branch tip and the merge is carried as a patch, which
# %prep applies. The catch-up direction is deliberate: the feature branch is far
# ahead of the release but only a little behind it, so "bring the branch up to
# the release" is a ~1.4M patch where "apply the branch onto the release" is
# ~5.9M for the identical tree.
#
# Conflicts are resolved two ways, and anything left over is a hard failure:
#   * files the feature branch deleted and the release still edits -> take the
#     deletion (the old renderer is gone on purpose);
#   * content conflicts -> replayed from the committed git-rerere cache in
#     merge/rr-cache, recorded by hand the first time each one appeared.
#
# Writes patches/0100-catch-up-to-release.patch and prints, on stdout:
#   VERSION=<merged project version>
#   TAG=<upstream release tag merged in>
#   BASE=<submodule commit the patch applies to>
# Everything else goes to stderr so callers can eval the stdout safely.
#
# Environment:
#   RELEASE_TAG=<tag>  merge this tag instead of the newest v* tag
set -euo pipefail

log() { printf 'merge-release: %s\n' "$*" >&2; }
die() { printf 'merge-release: error: %s\n' "$*" >&2; exit 1; }

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

SUB=lemonade
PATCH=patches/0100-catch-up-to-release.patch
RR_CACHE=merge/rr-cache

[ -e "$SUB/.git" ] || die "the $SUB submodule is not checked out; run: git submodule update --init $SUB"

# Release tags live on main, which a shallow or single-branch submodule clone may
# not have; make sure both the tags and main are present before resolving one.
log "fetching upstream tags"
git -C "$SUB" fetch --quiet --tags origin '+refs/heads/main:refs/remotes/origin/main'

TAG=${RELEASE_TAG:-$(git -C "$SUB" tag -l 'v[0-9]*' --sort=v:refname | tail -1)}
[ -n "$TAG" ] || die "no v* release tag found upstream"
git -C "$SUB" rev-parse -q --verify "$TAG^{commit}" >/dev/null \
    || die "$TAG is not a commit in the $SUB submodule"

BASE=$(git -C "$SUB" rev-parse HEAD)
log "merging $TAG into $(git -C "$SUB" rev-parse --short=9 HEAD)"

# Merge in a throwaway worktree so a failed or half-resolved merge never touches
# the submodule checkout that tito is about to archive.
WORKTREE=$(mktemp -d -t lemonade-merge-XXXXXX)
cleanup() {
    git -C "$SUB" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
    rm -rf "$WORKTREE"
}
trap cleanup EXIT

git -C "$SUB" worktree add -f --detach "$WORKTREE" "$BASE" >/dev/null 2>&1 \
    || die "could not create a merge worktree"

# rerere keys resolutions off the conflict text, so the cache has to sit in the
# worktree's git dir before the merge runs. Worktrees share the common dir.
COMMON_DIR=$(git -C "$WORKTREE" rev-parse --path-format=absolute --git-common-dir)
# Always clear first: the submodule's git dir keeps whatever a previous run left
# behind, and a stale resolution replaying silently is exactly the failure this
# script is supposed to make loud.
rm -rf "$COMMON_DIR/rr-cache"
if [ -d "$RR_CACHE" ]; then
    cp -a "$RR_CACHE" "$COMMON_DIR/rr-cache"
    log "loaded $(find "$RR_CACHE" -name postimage\* | wc -l) recorded conflict resolution(s)"
fi
git -C "$WORKTREE" config rerere.enabled true
git -C "$WORKTREE" config rerere.autoUpdate false

git -C "$WORKTREE" merge --no-commit --no-ff "$TAG" >&2 || true

# Files the feature branch deleted that the release still modifies: the deletion
# is the intended state, so stage it. The mirror case (upstream deleted a file
# the branch still edits) is genuinely ambiguous and is left to fail below.
mapfile -t DELETED_BY_US < <(git -C "$WORKTREE" status --porcelain | sed -n 's/^\(DU\|DD\) //p')
if [ ${#DELETED_BY_US[@]} -gt 0 ]; then
    log "taking the branch's deletion for ${#DELETED_BY_US[@]} file(s)"
    git -C "$WORKTREE" rm -q -- "${DELETED_BY_US[@]}"
fi

# rerere rewrites the working-tree file but deliberately leaves it unstaged so a
# human can look; stage every path it managed to finish.
mapfile -t STILL_CONFLICTED < <(git -C "$WORKTREE" rerere remaining)
mapfile -t UNMERGED < <(git -C "$WORKTREE" diff --name-only --diff-filter=U)
for path in "${UNMERGED[@]}"; do
    for unresolved in "${STILL_CONFLICTED[@]}"; do
        [ "$path" = "$unresolved" ] && continue 2
    done
    log "replayed a recorded resolution for $path"
    git -C "$WORKTREE" add -- "$path"
done

mapfile -t LEFTOVER < <(git -C "$WORKTREE" status --porcelain | sed -n 's/^\(DD\|AU\|UD\|UA\|DU\|AA\|UU\) //p')
if [ ${#LEFTOVER[@]} -gt 0 ]; then
    {
        echo "merge-release: error: $TAG conflicts with the branch in ways this script cannot resolve:"
        printf '    %s\n' "${LEFTOVER[@]}"
        echo "  Resolve them by hand once and record the resolution, then rerun:"
        echo "    git -C $SUB worktree add -f --detach /tmp/lemonade-merge $BASE"
        echo "    cd /tmp/lemonade-merge && git config rerere.enabled true"
        echo "    git merge --no-ff $TAG   # resolve, git add, git commit"
        echo "    cp -a \$(git rev-parse --git-common-dir)/rr-cache $REPO_ROOT/$RR_CACHE"
    } >&2
    exit 1
fi

git -C "$WORKTREE" -c user.name='lemonade-rpm nightly' \
    -c user.email='nightly@lemonade-rpm.invalid' \
    commit -q --no-verify -m "catch up to $TAG" >&2

VERSION=$(sed -n 's/^project(lemon_cpp VERSION \([0-9][0-9.]*\)).*/\1/p' "$WORKTREE/CMakeLists.txt")
[ -n "$VERSION" ] || die "could not read the project version from the merged CMakeLists.txt"

# --binary because the release adds a test audio fixture; without it the patch
# silently drops the file and %prep fails on a checksum mismatch.
mkdir -p patches
{
    echo "Bring the tracked feature branch up to upstream release $TAG."
    echo
    echo "Generated by scripts/merge-release.sh -- do not edit by hand."
    echo "Merges $TAG into $(git -C "$SUB" rev-parse --short=9 "$BASE") and ships the"
    echo "difference, so the built RPM carries the $VERSION release together with the"
    echo "front-end work that only exists on the branch."
    echo
    git -C "$WORKTREE" diff --binary "$BASE" HEAD
} > "$PATCH"

log "wrote $PATCH ($(wc -c < "$PATCH" | numfmt --to=iec), merged version $VERSION)"

# Persist any resolution rerere learned during this run. `thisimage` is scratch
# state for a merge in progress, so it is dropped rather than committed.
if [ -d "$COMMON_DIR/rr-cache" ]; then
    rm -rf "$RR_CACHE"
    mkdir -p "$(dirname "$RR_CACHE")"
    cp -a "$COMMON_DIR/rr-cache" "$RR_CACHE"
    find "$RR_CACHE" -name thisimage -delete
fi

echo "VERSION=$VERSION"
echo "TAG=$TAG"
echo "BASE=$BASE"
