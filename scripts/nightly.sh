#!/usr/bin/env bash
#
# Roll the vendored lemonade submodule forward to the tip of the tracked upstream
# branch and cut a snapshot release with tito.
#
# Version is taken from upstream's CMakeLists.txt; Release is stamped as
# 0.<utc-date>git<sha>%{?dist} so every nightly sorts below the eventual real
# release of the same version. Pushing the resulting tag is what triggers the
# COPR rebuild -- see README.md.
#
# Environment:
#   FORCE=1        cut a tag even when the upstream branch has not moved
#   PUSH=1         push the commits and the new tag to origin
#   BRANCH=<name>  override the tracked branch (default: submodule.lemonade.branch)
#   TITO_IMAGE=..  container image used when tito is not installed on the host
#
set -euo pipefail

log() { printf 'nightly: %s\n' "$*"; }
die() { printf 'nightly: error: %s\n' "$*" >&2; exit 1; }

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

FORCE=${FORCE:-0}
PUSH=${PUSH:-0}
TITO_IMAGE=${TITO_IMAGE:-registry.fedoraproject.org/fedora:44}
BRANCH=${BRANCH:-$(git config -f .gitmodules submodule.lemonade.branch || true)}
[ -n "$BRANCH" ] || die "no tracking branch set; add 'branch = <name>' to .gitmodules"

# tito refuses to tag a dirty tree, and it would bundle whatever is committed
# rather than what is on disk, so bail out early with a clearer message.
[ -z "$(git status --porcelain)" ] || die "working tree is dirty; commit or stash first"

LOCAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$LOCAL_BRANCH" != "HEAD" ] || die "HEAD is detached; check out a branch first"

# tito writes the %changelog entry from the git identity, so it must resolve.
if ! git config user.email >/dev/null 2>&1; then
    git config user.name "lemonade-rpm nightly"
    git config user.email "nightly@users.noreply.github.com"
fi
GIT_NAME=$(git config user.name)
GIT_EMAIL=$(git config user.email)

# Run tito on the host when it is available, otherwise in a throwaway Fedora
# container. Rootless podman maps container root onto the invoking user, so the
# files tito writes stay owned by us.
run_tito() {
    if command -v tito >/dev/null 2>&1; then
        tito "$@"
        return
    fi

    local engine
    engine=$(command -v podman || command -v docker) \
        || die "tito is not installed and neither podman nor docker was found"
    log "tito not installed; running it in $TITO_IMAGE via ${engine##*/}"

    "$engine" run --rm -i \
        -v "$REPO_ROOT:/src:z" -w /src \
        -e HOME=/tmp \
        -e "GIT_NAME=$GIT_NAME" -e "GIT_EMAIL=$GIT_EMAIL" \
        "$TITO_IMAGE" \
        bash -euc '
            dnf -y install --setopt=install_weak_deps=False tito git rpm-build >/dev/null
            git config --global user.name "$GIT_NAME"
            git config --global user.email "$GIT_EMAIL"
            git config --global --add safe.directory /src
            git config --global --add safe.directory /src/lemonade
            exec tito "$@"
        ' _ "$@"
}

OLD_SHA=$(git rev-parse "HEAD:lemonade")

log "updating the lemonade submodule to the tip of $BRANCH"
git submodule update --init --remote lemonade
NEW_SHA=$(git -C lemonade rev-parse HEAD)
SHORT_SHA=$(git -C lemonade rev-parse --short=9 HEAD)

if [ "$OLD_SHA" = "$NEW_SHA" ] && [ "$FORCE" != "1" ]; then
    log "$BRANCH is unchanged at $SHORT_SHA; nothing to build"
    exit 0
fi

VERSION=$(sed -n 's/^project(lemon_cpp VERSION \([0-9][0-9.]*\)).*/\1/p' lemonade/CMakeLists.txt)
[ -n "$VERSION" ] || die "could not read the project version from lemonade/CMakeLists.txt"

# A moving branch drifts out from under the patches; fail loudly rather than
# shipping a package that silently lost a downstream fix.
log "checking that the patches still apply to $BRANCH@$SHORT_SHA"
for patch in patches/*.patch; do
    git -C lemonade apply --check "../$patch" \
        || die "$patch no longer applies to $BRANCH@$SHORT_SHA; refresh it before retrying"
done

SPEC_VERSION=$(sed -n 's/^Version:[[:space:]]*//p' lemonade.spec)
if [ "$SPEC_VERSION" != "$VERSION" ]; then
    log "upstream version changed: $SPEC_VERSION -> $VERSION"
    sed -i "s/^Version:.*/Version:        $VERSION/" lemonade.spec
fi

git add lemonade lemonade.spec
if git diff --cached --quiet; then
    [ "$FORCE" = "1" ] || { log "no packaging changes; nothing to do"; exit 0; }
    log "no packaging changes; cutting a rebuild tag anyway (FORCE=1)"
else
    git commit -q \
        -m "nightly: $BRANCH @ $SHORT_SHA" \
        -m "https://github.com/lemonade-sdk/lemonade/commit/$NEW_SHA"
fi

# Cheap pre-flight: proves the spec still parses, that the submodule-aware
# tarball is produced under the name Source0 expects, and that every patch
# referenced by the spec exists. The compile itself is COPR's job.
if [ "${CHECK_SRPM:-1}" = "1" ]; then
    log "building a test SRPM before tagging"
    run_tito build --srpm --test --output=/tmp/tito-nightly >/dev/null \
        || die "test SRPM build failed; not tagging"
fi

RELEASE="0.$(date -u +%Y%m%d)git${SHORT_SHA}%{?dist}"
log "tagging $VERSION-$RELEASE"
run_tito tag --use-release "$RELEASE" --accept-auto-changelog

TAG=$(git describe --tags --abbrev=0)
log "created tag $TAG"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### Nightly snapshot"
        echo
        echo "| | |"
        echo "|---|---|"
        echo "| Tag | \`$TAG\` |"
        echo "| Upstream | [\`$SHORT_SHA\`](https://github.com/lemonade-sdk/lemonade/commit/$NEW_SHA) on \`$BRANCH\` |"
        echo "| Version | \`$VERSION-$RELEASE\` |"
    } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$PUSH" = "1" ]; then
    log "pushing $LOCAL_BRANCH and $TAG to origin"
    git push --follow-tags origin "$LOCAL_BRANCH"
else
    log "not pushing (set PUSH=1); review with: git show $TAG"
fi
