#!/usr/bin/env bash
#
# Roll the vendored lemonade submodule forward to the tip of the tracked upstream
# branch and cut a snapshot release with tito. The branch is built as-is, with
# no upstream release merged into it.
#
# Upstream derives its version from git state (tools/version.py), which the
# source tarball does not carry. The full upstream version string is therefore
# computed here and recorded in the spec, whose %prep writes it to the .version
# file version.py reads first. Version: is its numeric X.Y.Z part, since rpm tags
# cannot carry the ~<count>.<hash> suffix; Release is stamped as
# 0.<utc-date>git<sha>%{?dist}, which sorts nightlies correctly among themselves
# and below the matching upstream release. Pushing the resulting tag is what
# triggers the COPR rebuild -- see README.md.
#
# Environment:
#   FORCE=1        cut a tag even when nothing upstream has moved
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
    # .invalid is reserved (RFC 2606) so it can never resolve to a real
    # GitHub account; a bare name@users.noreply.github.com would credit
    # whoever owns that login. CI overrides this with github-actions[bot].
    git config user.name "lemonade-rpm nightly"
    git config user.email "nightly@lemonade-rpm.invalid"
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

log "updating the lemonade submodule to the tip of $BRANCH"
git submodule update --init lemonade
# Fetch the branch explicitly: a single-branch clone (as CI may make) would not
# have it under its default refspec.
git -C lemonade fetch --quiet origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
# version.py counts every commit reachable from HEAD, so a shallow clone would
# produce a wrong version rather than an error.
if [ "$(git -C lemonade rev-parse --is-shallow-repository)" = "true" ]; then
    git -C lemonade fetch --quiet --unshallow origin
fi
git -C lemonade checkout --quiet --detach "origin/$BRANCH"
NEW_SHA=$(git -C lemonade rev-parse HEAD)
SHORT_SHA=$(git -C lemonade rev-parse --short=9 HEAD)

# Ask upstream's own version.py, as their CI would. Its development versions are
# "the upcoming weekly release", judged from the current time; anchoring that to
# the commit date instead keeps the version a pure function of the commit, so an
# unmoved branch does not produce a new package just because a week turned over.
UPSTREAM_VERSION=$(cd lemonade && BRANCH="$BRANCH" python3 -c '
import datetime, os, subprocess, sys
from pathlib import Path
sys.path.insert(0, "tools")
from version import get_version
ts = subprocess.run(["git", "log", "-1", "--format=%ct", "HEAD"], check=True,
                    capture_output=True, text=True).stdout.strip()
now = datetime.datetime.fromtimestamp(int(ts), datetime.timezone.utc)
print(get_version(Path.cwd(), now=now, branch=os.environ["BRANCH"]))
') || die "could not compute the upstream version with tools/version.py"
VERSION=${UPSTREAM_VERSION%%~*}
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] \
    || die "unexpected upstream version '$UPSTREAM_VERSION'"
log "$BRANCH is at $SHORT_SHA, upstream version $UPSTREAM_VERSION"

# Any downstream patch the spec carries must still apply to the moving branch:
# shipping a package that silently lost a fix is worse than a failed nightly.
shopt -s nullglob
for patch in patches/*.patch; do
    git -C lemonade apply --check --binary "../$patch" \
        || die "$patch no longer applies to $BRANCH@$SHORT_SHA; refresh it before retrying"
done
shopt -u nullglob

SPEC_VERSION=$(sed -n 's/^Version:[[:space:]]*//p' lemonade.spec)
if [ "$SPEC_VERSION" != "$VERSION" ]; then
    log "upstream version changed: $SPEC_VERSION -> $VERSION"
    sed -i "s/^Version:.*/Version:        $VERSION/" lemonade.spec
fi
sed -i "s/^%global upstream_version .*/%global upstream_version $UPSTREAM_VERSION/" lemonade.spec
grep -qx "%global upstream_version $UPSTREAM_VERSION" lemonade.spec \
    || die "lemonade.spec has no '%global upstream_version' line to update"

git add lemonade lemonade.spec
if git diff --cached --quiet; then
    [ "$FORCE" = "1" ] || { log "no packaging changes; nothing to do"; exit 0; }
    log "no packaging changes; cutting a rebuild tag anyway (FORCE=1)"
else
    git commit -q \
        -m "nightly: $BRANCH @ $SHORT_SHA ($UPSTREAM_VERSION)" \
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

# The tag name is derived from the release string, which is just date + branch
# sha -- so re-cutting on the same day (FORCE=1 after a failed build, upstream
# not having moved) would collide with the tag already pushed. Append a serial
# in that case. rpm ranks a numeric segment above an alpha one, so
# 0.<date>.1git<sha> sorts above 0.<date>git<sha> and the re-cut wins.
RELEASE_DATE="0.$(date -u +%Y%m%d)"
SERIAL=""
N=0
while git rev-parse -q --verify \
        "refs/tags/lemonade-$VERSION-${RELEASE_DATE}${SERIAL}git${SHORT_SHA}" >/dev/null; do
    N=$((N + 1))
    SERIAL=".$N"
done
[ -z "$SERIAL" ] || log "a tag for today at $SHORT_SHA exists; re-cutting as serial $N"
RELEASE="${RELEASE_DATE}${SERIAL}git${SHORT_SHA}%{?dist}"
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
        echo "| Upstream version | \`$UPSTREAM_VERSION\` |"
        echo "| Version | \`$VERSION-$RELEASE\` |"
    } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$PUSH" = "1" ]; then
    log "pushing $LOCAL_BRANCH and $TAG to origin"
    git push --follow-tags origin "$LOCAL_BRANCH"
else
    log "not pushing (set PUSH=1); review with: git show $TAG"
fi
