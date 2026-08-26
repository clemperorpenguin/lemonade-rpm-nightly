# lemonade-rpm-nightly

[![Copr Build Status](https://copr.fedorainfracloud.org/coprs/clemperorpenguin/lemonade/package/lemonade/status_image/last_build.png)](https://copr.fedorainfracloud.org/coprs/clemperorpenguin/lemonade/)

Nightly Fedora RPM packages for [Lemonade](https://github.com/lemonade-sdk/lemonade), a lightweight, high-performance local LLM server.

This is a fork of the upstream `lemonade-rpm` packaging that builds the **newest upstream release**
with the **`GUI3_merging`** front-end work on top. Neither upstream branch has both: `GUI3_merging`
carries the new GUI but lags the released version, while a release tag has the version but not the
GUI. The source is integrated via a git submodule from
[lemonade-sdk/lemonade](https://github.com/lemonade-sdk/lemonade), pinned to the tip of that branch
and rolled forward once a day; the release is merged back in at package time as a generated patch.

> **These are snapshot builds of unreleased code.** They are versioned
> `<release-version>-0.<date>git<sha>` — the version of the newest upstream release, with a `Release`
> encoding the snapshot date and the branch commit. Nightlies sort correctly among themselves by date.
>
> **A nightly now outranks the matching stable release, so `dnf upgrade` will move you onto it.**
> That is a change: nightlies used to declare the branch's own lagging version (11.6.0 against a
> stable 11.7.0) and therefore sorted *below* stable and stayed opt-in. Now that the package carries
> the release's version, enabling this repo is enough to be upgraded onto snapshot code. If you want
> stable, do not enable this repo.
>
> Practically: enable **either** this repo **or**
> [abn/lemonade](https://copr.fedorainfracloud.org/coprs/abn/lemonade/), not both. To switch from
> stable to a nightly, install it explicitly:
>
> ```bash
> sudo dnf copr disable abn/lemonade
> sudo dnf copr enable clemperorpenguin/lemonade
> sudo dnf distro-sync --refresh 'lemonade*'
> ```

## Installation

This package is available via the [clemperorpenguin/lemonade](https://copr.fedorainfracloud.org/coprs/clemperorpenguin/lemonade/) Copr repository.

### Quick Start (Full Installation)

To install both the server and the desktop application:

```bash
# Enable the Copr repository
sudo dnf copr enable clemperorpenguin/lemonade

# Install everything
sudo dnf install lemonade
```

### Modular Installation

You can also install the components independently:

```bash
# Install only the command-line interface (CLI client)
sudo dnf install lemonade-cli

# Install only the system service server (headless multi-tenant background service)
# Note: This will automatically pull in lemonade-cli as a dependency
sudo dnf install lemonade-server

# Install only the embedded standalone server (portable, single-user, self-contained server)
# Note: Conflicts with lemonade-server; works with lemonade-web, tray, desktop, and cli
sudo dnf install lemonade-server-embedded

# Install only the system tray (lightweight GTK interface)
# Note: Requires lemonade-server or lemonade-server-embedded
sudo dnf install lemonade-tray

# Install only the desktop application
# Note: Requires lemonade-server or lemonade-server-embedded
sudo dnf install lemonade-desktop

# Install only the web interface launcher (opens the built-in web UI in a browser)
# Note: Requires lemonade-server or lemonade-server-embedded
sudo dnf install lemonade-web
```

## Post-Installation

### Core Server

The core server can run either as a system-wide service (started by root, available to all users) or as a per-user service (started by you, runs only during your session).

**System service** — suitable for servers or shared desktops:

```bash
# Start the server
sudo systemctl start lemond.service

# Enable the server to start at boot
sudo systemctl enable lemond.service
```

**User service** — suitable for personal desktops (no `sudo` required):

```bash
# Enable and start for the current user
systemctl --user enable --now lemond.service

# Stop and disable
systemctl --user disable --now lemond.service
```


> **Note:** Running both the system service and the user service at the same time will cause a port conflict. Use one or the other.

### Configuration

Lemonade can be configured by setting environment variables in configuration drop-in files: 

* **System-wide service**: Read from `/etc/default/lemond`.
* **Per-user service**: Read from `~/.config/lemonade/lemond.conf`.

> **Changed in 11.8.** These used to be drop-in directories (`/etc/lemonade/conf.d/*.conf` and
> `~/.config/lemonade/conf.d/*.conf`), each loaded in alphabetical order. Upstream replaced them with
> a single environment file per scope. On upgrade the package copies any settings you had in
> `/etc/lemonade/conf.d/*.conf` into `/etc/default/lemond`, skipping keys already set there; your
> original files are left as `.rpmsave`. **The per-user service is not migrated** — if you had
> `~/.config/lemonade/conf.d/*.conf`, move those settings into `~/.config/lemonade/lemond.conf`
> yourself.

#### Common Options
You can configure the server by adding options to a custom file (e.g., `50-custom.conf`):

| Variable | Description | Default (System) | Default (User) |
|---|---|---|---|
| `LEMONADE_PORT` | Port to listen on | `13305` | `13305` |
| `LEMONADE_HOST` | Host address to bind to | `127.0.0.1` | `127.0.0.1` |
| `LEMONADE_API_KEY` | Admin API key for auth | *(None)* | *(None)* |
| `LEMONADE_CACHE_DIR`| Root directory for state/cache | `/var/lib/lemonade` | `~/.cache/lemonade` |
| `HF_HOME` | Hugging Face download cache | `/var/lib/lemonade/huggingface` | `~/.cache/huggingface` |

#### Step-by-Step Example

To configure the system-wide service to use a custom port and require an API key:

1. Create a custom configuration file:
   ```bash
   sudo nano /etc/default/lemond
   ```
2. Add your settings:
   ```ini
   LEMONADE_PORT=15000
   LEMONADE_API_KEY=your_secure_admin_key
   ```
3. Restart the service to apply changes:
   ```bash
   sudo systemctl restart lemond.service
   ```

*(Note: For the per-user service, edit `~/.config/lemonade/lemond.conf` and run `systemctl --user restart lemond.service` instead).*


### Command-Line Interface (CLI)

The `lemonade-cli` package installs the `lemonade` command-line client, which allows you to interact with a running Lemonade server (`lemond`):

```bash
sudo dnf install lemonade-cli
```

Use `lemonade --help` to list all available commands.

### System Tray (Desktop Users)

For a graphical interface in your system tray, install the `lemonade-tray` package:

```bash
sudo dnf install lemonade-tray
```

Launch it from your application menu (search for "Lemonade Tray"), or run `lemonade-tray` directly. To have it start automatically at login, add it via your desktop environment's autostart settings (e.g. GNOME Tweaks → Startup Applications).

Once started, a Lemonade icon will appear in your system tray, providing quick access to logs, settings, and the web interface.

### Web Interface

The `lemonade-web` package installs a `lemonade-web` launcher and a desktop entry that open the server's built-in web UI in your browser. The web UI is served by `lemond` at `http://localhost:13305/lemonade` and requires the server to be running.

### Desktop Application

The `lemonade-desktop` package installs the `lemonade-app` Tauri desktop application, available from your application menu as "Lemonade Desktop". It connects to a running `lemond` instance.

System-wide configuration lives in `/etc/default/lemond`. For the user service, per-user overrides go in `~/.config/lemonade/lemond.conf`.

## Upstream Differences & Migrations

### Comparison with Upstream CPack RPMs

Our packaging differs from the official monolithic RPM generated by the upstream CPack workflow in several key ways:

1. **Modular Subpackaging**: 
   * **Upstream**: Bundles everything (server, CLI, assets, desktop app) into a single monolithic `lemonade-server` package.
   * **Our RPM**: Splits components into modular subpackages (`lemonade-server`, `lemonade-cli`, `lemonade-tray`, `lemonade-desktop`, and `lemonade-web`). This allows headless server systems to install only the server or CLI subpackage without pulling in heavy GUI dependencies like GTK3, WebKit2GTK, Node.js, or Rust.
2. **Standard File Paths**:
   * **Upstream**: Configures the `lemonade` user with home directory `/opt/var/lib/lemonade`.
   * **Our RPM**: Follows standard Fedora guidelines, placing the user's home/state directory at `/var/lib/lemonade` (`%{_sharedstatedir}/lemonade`).
3. **Declared Dependencies**:
   * Our spec file lists complete, verified build and runtime dependencies for each component (including `jq` for the web launcher), whereas upstream's CPack package has limited hardcoded requirements.

---

### Key Changes & Migrations (Version >= 10.9.0-2)

If you are upgrading from `lemonade <= 10.9.0-1` (or migrating from the upstream CPack RPM), the package performs **automatic, safe migrations** during installation:

#### 1. Home Directory Migration (Upstream CPack to Local RPM)
* **What changed**: The `lemonade` user's home directory has been standardized to `/var/lib/lemonade`.
* **Migration**: The package post-install script automatically detects if the `lemonade` user is configured with the non-standard `/opt/var/lib/lemonade` path, stops the system service if active, updates the home directory to `/var/lib/lemonade`, and moves all existing files safely (`usermod -d -m`).

#### 2. Flattened Cache Directory (Un-nesting state files)
* **What changed**: The system service now runs with default environment variables (`LEMONADE_CACHE_DIR=/var/lib/lemonade` and `HF_HOME=/var/lib/lemonade/huggingface`). These lived in `/etc/lemonade/conf.d/10-paths.conf` until 11.8 and are appended to `/etc/default/lemond` from then on.
* **Migration**: Previously, config, binaries, and downloaded models were nested inside hidden directories:
  * `/var/lib/lemonade/.cache/lemonade/` (Config/Binaries)
  * `/var/lib/lemonade/.cache/huggingface/` (HuggingFace Models)
  
  Upon upgrade, the package automatically moves files from the nested `.cache/` directories to their new flat locations (`/var/lib/lemonade/` and `/var/lib/lemonade/huggingface/`) so that your configurations and downloaded models are preserved.
  
  *Note: This change does not affect the per-user service (`systemctl --user`), which continues to use standard isolated paths under user home directories.*

#### 3. GPU/NPU Hardware Acceleration Group Memberships
* **What changed**: To access direct rendering devices (like AMD GPUs, Ryzen NPUs, and Intel/NVIDIA cards) at `/dev/dri/renderD*`, the system service user must belong to the appropriate group.
* **Upgrade action**: The post-install script automatically adds the system `lemonade` user to the `render` and `video` groups (if they exist on the host) so that hardware acceleration works out of the box.

#### 4. Tauri Desktop App Configuration Path
* **What changed**: The Tauri desktop interface (`lemonade-desktop`) now stores settings under the standard XDG path `~/.config/lemonade/app_settings.json` instead of `~/.cache/lemonade/app_settings.json`. Settings are automatically migrated forward on first launch.

## Development

This fork exists to publish **nightly snapshots** that combine the newest upstream release with the
`GUI3_merging` branch. It uses [tito](https://github.com/rpm-software-management/tito) for versioning
and release management, the same as its parent repo — the differences are that the submodule tracks a
branch, the release string encodes a snapshot instead of being hand-bumped, and the release is merged
into the branch by a generated patch.

### Why a patch and not a merge commit

The package needs a tree that exists nowhere upstream: the branch merged with the release. COPR
resolves the submodule by cloning it at build time, so any merge commit would have to be fetchable
from a repository COPR can reach — which would mean maintaining a fork of `lemonade` itself. Instead
the submodule stays pinned to upstream's own branch tip and the merge ships as `Patch0`.

The patch runs *from* the branch *to* the release, which is the cheap direction: the branch is a few
hundred commits ahead of its fork point but only a few dozen behind the release, so "bring the branch
up to the release" is ~1.4 MB where "apply the branch onto the release" is ~5.9 MB for an identical
tree.

[`scripts/merge-release.sh`](scripts/merge-release.sh) generates it. Conflicts are handled two ways:

* files the branch **deleted** and the release still edits — the old React renderer — are resolved by
  taking the deletion;
* **content** conflicts are replayed from the [git rerere](https://git-scm.com/docs/git-rerere) cache
  committed at `merge/rr-cache`, recorded by hand the first time each one appeared.

Anything else is a hard failure. The script prints the exact commands to resolve a new conflict once
and record it; until someone does, the nightly stops rather than shipping a tree nobody has looked at.

### How a nightly happens

1. `.github/workflows/nightly.yml` runs at 04:17 UTC (and on demand via **Actions → nightly → Run workflow**).
2. It calls [`scripts/nightly.sh`](scripts/nightly.sh), which:
   - rolls the `lemonade` submodule to the tip of `GUI3_merging` (`git submodule update --remote`);
   - runs `scripts/merge-release.sh` to merge the newest upstream `v*` tag into that tip and regenerate
     `patches/0100-catch-up-to-release.patch`;
   - takes `Version:` from the *merged* tree's `project(lemon_cpp VERSION …)` and syncs it into the spec;
   - verifies every patch in `patches/` still applies, failing loudly if the branch drifted out from under one;
   - exits quietly if none of that changed anything;
   - builds a test SRPM as a pre-flight check;
   - runs `tito tag --use-release '0.<date>git<sha>%{?dist}' --accept-auto-changelog`;
   - pushes the commit and the tag to `main`.
3. Pushing the tag fires the COPR webhook, which rebuilds `clemperorpenguin/lemonade` from this repo.

Note that step 2 runs even when the branch has not moved: upstream tagging a new release changes the
package on its own, so that alone is a reason to cut a nightly.

Failures show up in two places: merge, patch and spec problems fail the GitHub Actions run, and
compile problems fail the COPR build. Check both if a night goes missing.

### Running the nightly by hand

```bash
# Dry run: update, tag locally, but do not push
./scripts/nightly.sh

# What CI does
PUSH=1 ./scripts/nightly.sh

# Re-cut a tag even though upstream has not moved (e.g. after a spec fix)
FORCE=1 PUSH=1 ./scripts/nightly.sh

# Track a different upstream branch for one run
BRANCH=main ./scripts/nightly.sh

# Merge a specific release instead of the newest v* tag
RELEASE_TAG=v11.7.0 ./scripts/nightly.sh

# Regenerate just the catch-up patch, without tagging
./scripts/merge-release.sh
```

The script uses `tito` from `$PATH` when present; otherwise it runs tito inside a throwaway Fedora
container (`podman` or `docker`, overridable with `TITO_IMAGE`). On an image-mode host such as
secureblue, `/etc/containers/policy.json` may reject unsigned registries — either add a user policy
at `~/.config/containers/policy.json` or just let the GitHub Actions workflow do the work.

### Changing the tracked branch

The branch lives in `.gitmodules`; everything else reads it from there.

```bash
git config -f .gitmodules submodule.lemonade.branch some-other-branch
git submodule sync lemonade
git commit -am "track some-other-branch"
```

### Building RPMs locally

Always commit first — tito only builds committed files.

```bash
# 1. Start the rpmbuilder container in the background
podman run -d --rm -i --name rpmbuilder-lemonade -v ${PWD}:/sources:z quay.io/abn/rpmbuilder:fedora-44 sleep inf

# 2. Trigger the build inside the container
podman exec rpmbuilder-lemonade rpmbuilder

# 3. Clean up
podman stop rpmbuilder-lemonade
```

The built RPM packages end up in `/output` inside the container. A host build (`tito build --rpm --test`)
works too if every `BuildRequires:` is already installed.

### COPR project configuration

The COPR project `clemperorpenguin/lemonade` needs one package wired to this repo:

| Setting | Value |
|---|---|
| Package name | `lemonade` |
| Source type | `Custom SCM` |
| Clone url | `https://github.com/clemperorpenguin/lemonade-rpm-nightly.git` |
| Committish | *(empty — the webhook supplies it)* |
| Subdirectory | *(empty)* |
| Spec file | `lemonade.spec` |
| Type of source | `tito` |
| Auto-rebuild | enabled |

Then copy the webhook URL from **COPR → project → Settings → Integrations** into
**GitHub → repo → Settings → Webhooks** with content type `application/json` and "Just the push event"
(tag pushes are push events).

To kick off a build without waiting for the webhook:

```bash
copr-cli build-package --name lemonade clemperorpenguin/lemonade
```

### Upgrading to a specific upstream release

If you ever need to pin a tagged release rather than a branch snapshot, the
[`bump-lemonade-version`](.agents/skills/bump-lemonade-version/SKILL.md) skill still describes that
workflow.
