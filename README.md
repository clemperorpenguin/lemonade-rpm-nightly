# lemonade-rpm-nightly

[![Copr Build Status](https://copr.fedorainfracloud.org/coprs/clemperorpenguin/lemonade/package/lemonade/status_image/last_build.png)](https://copr.fedorainfracloud.org/coprs/clemperorpenguin/lemonade/)

Nightly Fedora RPM packages for [Lemonade](https://github.com/lemonade-sdk/lemonade), a lightweight, high-performance local LLM server.

This is a fork of the upstream `lemonade-rpm` packaging that tracks the **`GUI3_merging`** development
branch instead of tagged releases. The source is integrated via a git submodule from
[lemonade-sdk/lemonade](https://github.com/lemonade-sdk/lemonade), rolled forward to the tip of that
branch once a day.

> **These are snapshot builds of unreleased code.** They are versioned
> `<upstream-version>-0.<date>git<sha>`, where `<upstream-version>` is whatever the branch's
> `CMakeLists.txt` declares. That deliberately sorts *below* a real release of the same version, and
> nightlies sort correctly among themselves by date.
>
> Note that `GUI3_merging` is a long-lived feature branch: it currently declares **11.6.0** while
> upstream has already released **11.7.0** on `main` (the branch is a few hundred commits ahead of its
> fork point but several dozen behind main, and contains neither the `v11.6.0` nor the `v11.7.0` tag).
> So a nightly sorts below stable 11.7.0 and `dnf upgrade` will not move you onto it. This corrects
> itself as soon as the branch merges `main` and inherits the newer version.
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

* **System-wide service**: Read from `/etc/lemonade/conf.d/*.conf` (loaded in alphabetical order).
* **Per-user service**: Read from `~/.config/lemonade/conf.d/*.conf`.

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
   sudo nano /etc/lemonade/conf.d/50-custom.conf
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

*(Note: For the per-user service, create `~/.config/lemonade/conf.d/50-custom.conf` and run `systemctl --user restart lemond.service` instead).*


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

System-wide configuration files are located in `/etc/lemonade/conf.d/`. For the user service, per-user overrides go in `~/.config/lemonade/conf.d/`.

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
* **What changed**: The system service now runs with default environment variables (`LEMONADE_CACHE_DIR=/var/lib/lemonade` and `HF_HOME=/var/lib/lemonade/huggingface`) defined in `/etc/lemonade/conf.d/10-paths.conf`.
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

This fork exists to publish **nightly snapshots** of the upstream `GUI3_merging` branch. It uses
[tito](https://github.com/rpm-software-management/tito) for versioning and release management, the
same as its parent repo — the only difference is that the submodule tracks a branch and the release
string encodes a snapshot instead of being hand-bumped.

### How a nightly happens

1. `.github/workflows/nightly.yml` runs at 04:17 UTC (and on demand via **Actions → nightly → Run workflow**).
2. It calls [`scripts/nightly.sh`](scripts/nightly.sh), which:
   - rolls the `lemonade` submodule to the tip of `GUI3_merging` (`git submodule update --remote`);
   - exits quietly if the branch has not moved since the last snapshot;
   - reads `Version:` from upstream's `project(lemon_cpp VERSION …)` and syncs it into the spec;
   - verifies every patch in `patches/` still applies, failing loudly if the branch drifted out from under one;
   - builds a test SRPM as a pre-flight check;
   - runs `tito tag --use-release '0.<date>git<sha>%{?dist}' --accept-auto-changelog`;
   - pushes the commit and the tag to `main`.
3. Pushing the tag fires the COPR webhook, which rebuilds `clemperorpenguin/lemonade` from this repo.

Failures show up in two places: patch/spec problems fail the GitHub Actions run, and compile problems
fail the COPR build. Check both if a night goes missing.

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
