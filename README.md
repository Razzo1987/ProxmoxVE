# Razzo Scripts — ProxmoxVE

Personal collection of Proxmox VE LXC helper scripts, built **on top of**
[community-scripts/core](https://github.com/community-scripts/core) rather than
forking it. The engine (`build.func`, `install.func`, `tools.func`, everything
under `core/`, `ui/`, `lib/`, …) is always fetched from upstream at runtime; this
repository only ships the three per-application files and its own branding.

> These scripts are not affiliated with, endorsed by, or supported by the
> community-scripts organisation. Use them at your own risk.

---

## Usage

Run on a **Proxmox VE host**, as root, from the shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Razzo1987/ProxmoxVE/main/ct/<app>.sh)"
```

For example:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Razzo1987/ProxmoxVE/main/ct/datahub.sh)"
```

Re-running the same command against an existing container enters the update
flow instead of creating a new one.

To test against a fork or branch of the engine:

```bash
COMMUNITY_SCRIPTS_CORE_URL=https://raw.githubusercontent.com/<you>/core/<branch> \
  bash -c "$(curl -fsSL .../ct/<app>.sh)"
```

---

## Available scripts

| App | Script | Method | Default resources | Port | Status |
|---|---|---|---|---|---|
| **DataHub** | [ct/datahub.sh](ct/datahub.sh) | Docker Compose | 4 vCPU / 12 GB / 60 GB | 9002 | Tested, working |
| **OpenMetadata** | [ct/openmetadata.sh](ct/openmetadata.sh) | Docker Compose | 4 vCPU / 12 GB / 60 GB | 8585 | Tested, working |
| **OpenMetadata (bare-metal)** | [ct/openmetadata-baremetal.sh](ct/openmetadata-baremetal.sh) | Bare-metal | 4 vCPU / 16 GB / 150 GB | 8585 | **Broken — do not use** |
| **Dummy** | [ct/dummy.sh](ct/dummy.sh) | — | 1 vCPU / 512 MB / 4 GB | 3000 | Template |

All containers default to **Debian 13**, unprivileged.

### Notes per app

- **DataHub** — GMS, Frontend, MySQL, Elasticsearch and Kafka in a single CT.
  Upstream publishes no bare-metal install path. Default login `datahub` /
  `datahub`. First boot takes several minutes while Kafka and Elasticsearch
  bootstrap.
- **OpenMetadata** — deployed from the `docker-compose.yml` asset attached to
  each upstream release (server, ingestion/Airflow, MySQL, Elasticsearch). The
  asset pins every image tag and requires no `.env`. Default login
  `admin@open-metadata.org` / `admin`; Airflow ingestion UI on port 8080.
- **OpenMetadata (bare-metal)** — kept only as a record of the attempt. It hangs
  indefinitely at `./bootstrap/openmetadata-ops.sh drop-create`: upstream
  requires MySQL 8.0.42+ or PostgreSQL 15+, and the script falls back to
  Debian's MariaDB because `repo.mysql.com` ships an expired signing key on
  Debian 13. Use the Docker variant.
- **Dummy** — reference template. Copy these three files when adding a new app.

---

## Repository layout

```
ct/<app>.sh                 # entry point: metadata, branding, update_script()
install/<app>-install.sh    # runs inside the container
json/<app>.json             # metadata (resources, ports, notes, credentials)
AGENTS.md                   # conventions, anti-patterns, contribution rules
```

`ct/<app>.sh` derives the other two names: the engine computes
`NSAPP=$(echo "${APP,,}" | tr -d ' ')` and loads `install/<nsapp>-install.sh`.
`NSAPP` is also the container's default hostname, so **use hyphens, never
underscores**, in `APP`.

---

## Local conventions

Everything in [AGENTS.md](AGENTS.md) applies. The points specific to this
repository:

1. **`COMMUNITY_SCRIPTS_URL` is pinned** at the top of every `ct/<app>.sh`.
   When curl-piped, the engine cannot infer which repository the script came
   from and would default to `community-scripts/ProxmoxVED`, 404-ing on
   `install/`.
2. **Custom `custom_header()`** instead of `header_info "$APP"`, which fetches a
   banner from a path that only exists for upstream-generated apps.
3. **Custom `custom_description()`** instead of the engine's `description()`,
   which writes community-scripts-branded HTML into the container description.
4. **The `community-script` tag stays.** `base_settings()` / `advanced_settings()`
   prepend it unconditionally; `razzo-script` is added alongside, not instead.
   Final tags look like `community-script;razzo-script;<app tags>`.
5. **Docker is a documented exception, not the norm.** It is used only where
   upstream ships no bare-metal install path (DataHub, OpenMetadata). Such
   scripts carry a `docker` tag and a `warning` note in their JSON explaining
   why.

---

## Adding a new app

Copy the `dummy` triplet and adapt it:

```
ct/dummy.sh               →  ct/<app>.sh
install/dummy-install.sh  →  install/<app>-install.sh
json/dummy.json           →  json/<app>.json
```

Then work through the checklist in [AGENTS.md](AGENTS.md) — in particular: use
`setup_*` helpers instead of hand-rolled runtime installs, never wrap
`tools.func` functions in `msg_info`/`msg_ok` blocks (they print their own), and
prefix every `apt`/`npm`/build command with `$STD`.

---

## Credits

The engine and all helper functions come from
[community-scripts/core](https://github.com/community-scripts/core), originally
by [tteck](https://github.com/tteck). MIT licensed.
