# Livebook Infrastructure & CI/CD Patterns

> **Repository:** [livebook-dev/livebook](https://github.com/livebook-dev/livebook)
> **Base image:** `ghcr.io/livebook-dev/livebook`
> **Tech stack:** Elixir (Phoenix/LiveView), Tauri (Rust), Bun/Vite/Tailwind, protobuf

---

## 1. GitHub Actions Workflows

Two workflow files in `.github/workflows/`.

### 1.1. CI (`ci.yml`)

**Purpose:** Runs on every PR and push to `main`/`v*.*` branches.

| Step | Detail |
|------|--------|
| **Versions** | Reads `./versions` file for `elixir`, `otp` versions (line 21-23) |
| **Erlang/Elixir** | `erlef/setup-beam@v1` with strict pinning |
| **Cache** | Mix deps + `_build` keyed on `runner.os-elixir-otp-hashFiles('**/mix.lock')` |
| **Bun cache** | `~/.bun/install/cache` keyed on `assets/bun.lock` |
| **Formatting** | `mix format --check-formatted` (line 52) |
| **Warnings** | `mix compile --warnings-as-errors` (line 55) |
| **Tests** | `mix test` with `TEST_GIT_SSH_KEY` secret (line 58-60) |
| **Bun deps** | `mix bun.install` then `mix bun assets install` (line 62-65) |
| **Assets format** | `mix bun assets run format-check` (line 68) |
| **Assets test** | `mix bun assets run test` (line 71) |

```yaml
# Line 13-14 — env set at job level
env:
  MIX_ENV: test
```

```yaml
# Line 19-23 — dynamic version loading
- name: Read ./versions
  run: |
    . versions
    echo "elixir=$elixir" >> $GITHUB_ENV
    echo "otp=$otp" >> $GITHUB_ENV
```

**Windows** job runs only on `push` events (line 76: `if: github.event_name == 'push'`). It uses `ilammy/msvc-dev-cmd@v1` for native compilation and `git config --global core.autocrlf input`.

### 1.2. Release (`release.yml`)

**Triggers:** Tag push (`v*.*.*`), daily midnight cron, manual `workflow_dispatch` (nightly).

**Permissions:** Minimum — `contents: read`, elevated to `contents: write` and `packages: write` per-job.

#### Job: `create_release`
- Creates a **draft** GitHub Release for tags
- Creates/updates a `nightly` release for cron/manual runs

#### Job: `app` — Desktop builds (matrix, 5 platforms)

| Platform | `gui_target` |
|----------|-------------|
| `macos-15` | `aarch64-apple-darwin` |
| `macos-15-intel` | `x86_64-apple-darwin` |
| `windows-2022` | `x86_64-pc-windows-msvc` |
| `ubuntu-22.04-arm` | `aarch64-unknown-linux-gnu` |
| `ubuntu-22.04` | `x86_64-unknown-linux-gnu` |

Key steps:
1. Read versions (same pattern as CI)
2. Setup Erlang/Elixir + Rust (`dtolnay/rust-toolchain@stable`)
3. Rust cache via `Swatinem/rust-cache@v2` with `workspaces: rel/app/src-tauri`
4. Linux deps: libwebkit2gtk-4.1-dev, libgtk-3-dev, etc.
5. Install Tauri CLI (`cargo install tauri-cli --version "=2.8.0" --locked`)
6. **Codesigning secrets** (lines 186-201):

```yaml
# macOS codesigning
APPLE_CERTIFICATE: ${{ secrets.APPLE_CERTIFICATE_P12_BASE64 }}
APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_P12_PASSWORD }}
APPLE_SIGNING_IDENTITY: ${{ secrets.APPLE_SIGNING_IDENTITY }}
APPLE_ID: ${{ secrets.APPLE_ID }}
APPLE_PASSWORD: ${{ secrets.APPLE_PASSWORD }}
APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
# Windows codesigning (Azure Trusted Signing)
AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
AZURE_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
AZURE_TRUSTED_SIGNING_ACCOUNT_NAME: ${{ secrets.AZURE_TRUSTED_SIGNING_ACCOUNT_NAME }}
AZURE_CERTIFICATE_PROFILE_NAME: ${{ secrets.AZURE_CERTIFICATE_PROFILE_NAME }}
# Tauri updater key
TAURI_SIGNING_PRIVATE_KEY: ${{ secrets.TAURI_SIGNING_PRIVATE_KEY }}
TAURI_SIGNING_PRIVATE_KEY_PASSWORD: ${{ secrets.TAURI_SIGNING_PRIVATE_KEY_PASSWORD }}
```

7. Build via `tauri-apps/tauri-action@v0.6` with `projectPath: rel/app`, `tauriScript: ./tauri.sh`

#### Job: `docker` — Multi-arch Docker builds

```yaml
# Line 229-239 — matrix variants
matrix:
  include:
    - name: "default"
      suffix: ""
      build_args: |
        VARIANT=default
    - name: "cuda12"
      tag_suffix: "-cuda12"
      build_args: |
        VARIANT=cuda
        CUDA_VERSION_MAJOR=12
        CUDA_VERSION_MINOR=8
```

Key patterns:
- QEMU + Buildx for multi-platform (`linux/amd64,linux/arm64`)
- `docker/metadata-action@v5` for tag generation (semver + nightly)
- GitHub Container Registry login with `GITHUB_TOKEN`
- Build cache: `type=gha` with `mode=max`
- Base image passed as build arg: `hexpm/elixir:$elixir-erlang-$otp-ubuntu-$ubuntu`

---

## 2. Docker

### Dockerfile (`Dockerfile`)

**Multi-stage build with build args for variant selection:**

```dockerfile
# Line 1-3 — flexible base image
ARG BASE_IMAGE
ARG VARIANT

FROM ${BASE_IMAGE} AS base-default
FROM ${BASE_IMAGE} AS base-cuda
```

**CUDA variant** installs `cuda-nvcc`, `cuda-libraries`, `libcudnn9`, `libnccl2` (line 22-25).

**Build stage** (`FROM base-${VARIANT} AS build`):
- `ENV MIX_ENV=prod` (line 52)
- Copies `mix.exs`/`mix.lock` first, then `deps.get` + `deps.compile` (caching layer)
- Then copies full source and runs: `mix do compile + assets.setup + release livebook` (line 68)
- `ENV ERL_FLAGS="+JMsingle true"` — disables JIT under QEMU (line 45)

**Final stage**:
- Keeps Erlang/Elixir/Mix available (not a typical Elixir release — `include_erts: false`)
- `WORKDIR /data` with `ENV LIVEBOOK_HOME=/data` — easy volume mounting
- `ENV LIVEBOOK_IP="::"` — binds to all interfaces (line 112)
- `chmod -R go=u /app` — allows `--user` flag (line 121)
- `HEALTHCHECK CMD wget ... /public/health` (line 125)
- `CMD [ "/app/bin/server" ]` (line 127)

### .dockerignore

```dockerfile
# Line 17 — excludes desktop app build artifacts
/rel/app
```

---

## 3. Secrets & Environment Variables

### Pattern: `lib/livebook/config.ex` — typed env var parsing

Every environment variable has a dedicated parser function with validation:

```elixir
# lib/livebook/config.ex, line 461-472
def secret!(env) do
  if secret_key_base = System.get_env(env) do
    if byte_size(secret_key_base) < 64 do
      abort!(
        "cannot start Livebook because #{env} must be at least 64 characters. " <>
          "Invoke `openssl rand -base64 48` to generate an appropriately long secret."
      )
    end
    secret_key_base
  end
end
```

### Pattern: `lib/livebook.ex` — runtime configuration

```elixir
# lib/livebook.ex, line 84
def config_runtime do
  # Load user extensions from RELEASE_ROOT/user/extensions/
  if root = System.get_env("RELEASE_ROOT") do
    for file <- Path.wildcard(Path.join(root, "user/extensions/*.exs")) do
      Code.require_file(file)
    end
  end

  # Then read ~30 env vars via Livebook.Config.* helpers
  config :livebook, LivebookWeb.Endpoint,
    secret_key_base:
      Livebook.Config.secret!("LIVEBOOK_SECRET_KEY_BASE") ||
        Livebook.Utils.random_secret_key_base()
  # ... port, ip, password, clustering, etc.
end
```

Key environment variables:

| Variable | Validation | Default |
|----------|-----------|---------|
| `LIVEBOOK_SECRET_KEY_BASE` | min 64 chars | random |
| `LIVEBOOK_PASSWORD` | min 12 chars | token auth |
| `LIVEBOOK_PORT` | non-negative int | 8080 |
| `LIVEBOOK_IP` | valid IPv4/IPv6 | 127.0.0.1 |
| `LIVEBOOK_COOKIE` | atom | random |
| `LIVEBOOK_NODE` | atom | — |
| `LIVEBOOK_CLUSTER` | `dns:query` | — |
| `LIVEBOOK_LOG_LEVEL` | error/warning/notice/info/debug | warning |
| `LIVEBOOK_LOG_FORMAT` | text/json | text |

### Secrets from files (k8s pattern)

The Kubernetes deployment docs (`docs/deployment/docker.md` lines 110-124) show secrets from `Secret` resources:

```yaml
- name: LIVEBOOK_PASSWORD
  valueFrom:
    secretKeyRef:
      name: livebook-secret
      key: LIVEBOOK_PASSWORD
```

---

## 4. Configuration Files

| File | Purpose |
|------|---------|
| `config/config.exs` | Shared config — endpoint, logger, bun, MIME types |
| `config/dev.exs` | Dev — code reloading, watchers, auth disabled, port 4000 |
| `config/prod.exs` | Prod — port 8080, iframe port 8081, log level warning |
| `config/runtime.exs` | Delegates to `Livebook.config_runtime()` |
| `config/test.exs` | Test — auth disabled, JSON logger, port 4002 |

**Compiler pipeline** in `mix.exs` line 21:
```elixir
compilers: [:phoenix_live_view] ++ Mix.compilers() ++ [:ensure_livebook_priv]
```

---

## 5. Releases

Defined in `mix.exs` lines 185-207:

```elixir
defp releases do
  [
    livebook: [
      applications: @release_apps,
      include_executables_for: [:unix, :windows],
      include_erts: false,          # Erlang must be available at runtime
      rel_templates_path: "rel/server",
      steps: [:assemble, &remove_cookie/1, &write_runtime_modules/1]
    ],
    app: [
      applications: @release_apps,
      include_erts: false,
      rel_templates_path: "rel/#{Mix.target()}",
      steps: [
        :assemble,
        &remove_cookie/1,
        &standalone_erlang_elixir/1,
        &ElixirKit.Release.codesign/1
      ],
      entitlements: "rel/app/src-tauri/App.entitlements"
    ]
  ]
end
```

**Two distinct release types:**

### Server release (`rel/server/`)
- Custom `env.sh.eex` handles auto-clustering for Fly.io, ECS, k8s
- `vm.args.eex`: custom EPMD module, disables busy waiting
- `remote.vm.args.eex`: for `rpc`/`remote` commands
- Overlay `bin/server` script: handles EPMD daemon, FLAME, runtime nodes, and normal boot
- `bin/start_runtime.exs`: k8s/Fly-specific runtime node boot
- `bin/start_flame.exs`: FLAME node bootstrap with `Mix.install`

### App release (`rel/app/`) — Tauri desktop
- `standalone.exs` bundles OTP, Elixir, Hex, Rebar3 into the release
- `env.sh.eex`: sources `~/.livebookdesktop.sh`, sets vendor paths, default port 32123
- `tauri.sh`: orchestrates `mix release app` + `cargo tauri build`
- Rust binds to Elixir via `elixirkit` (ZeroMQ-based PubSub)

---

## 6. Clustering

**Docs:** `docs/deployment/clustering.md`

### Modes

| Mode | Mechanism |
|------|-----------|
| `auto` | Auto-detects platform (Fly.io DNS, ECS metadata API, k8s) |
| `dns:QUERY` | DNS-based A/AAAA record discovery |
| Livebook Teams | One-click deploy with clustering templates |

### Custom EPMD

Livebook uses a **custom EPMD module** (`Livebook.EPMD`) instead of the standard Erlang Port Mapper Daemon:

```
# rel/server/vm.args.eex, line 11
-epmd_module Elixir.Livebook.EPMD -kernel inet_dist_listen_min 13825
```

The remote variant (`remote.vm.args.eex`) uses `-dist_listen false -start_epmd false`.

### Kubernetes clustering

From `docs/deployment/docker.md` — headless service + DNS-based clustering:

```yaml
# Lines 50-57
apiVersion: v1
kind: Service
metadata:
  name: livebook-headless
spec:
  clusterIP: None
  selector:
    app: livebook
```

---

## 7. Desktop App — Tauri

### Architecture

```
Tauri (Rust shell) ←→ ElixirKit (ZeroMQ PubSub) ←→ Elixir BEAM
```

### Key Rust file: `rel/app/src-tauri/src/lib.rs` (666 lines)

- **Single-instance** enforcement (`tauri-plugin-single-instance`)
- **Deep link** handler (`livebook://` scheme)
- **Tray icon** with menu: Open, New, Copy URL, Logs, Settings, Updates, Quit
- **ElixirKit PubSub** over TCP — sends `open:` messages to Elixir, receives `ready:` messages
- **Auto-updater** (`tauri-plugin-updater`) — checks GitHub releases, prompts user

### `lib.rs` — Starting Elixir (lines 152-202)

```rust
// Debug: runs mix phx.server
let mut cmd = elixirkit::mix("phx.server", &[]);
cmd.env("ELIXIRKIT_PUBSUB", pubsub.url());
cmd.current_dir(mix_root);
cmd.env("MIX_TARGET", "app");

// Release: runs the bundled release
let release_dir = handle.path().resource_dir().unwrap().join("rel");
let mut cmd = elixirkit::release(&release_dir, "app");
```

### `tauri.conf.json`

```json
{
  "identifier": "dev.livebook.Livebook",
  "bundle": {
    "targets": ["app", "dmg", "nsis", "appimage"],
    "createUpdaterArtifacts": true,
    "fileAssociations": [{ "ext": ["livemd"], "mimeType": "text/x-livebook" }]
  },
  "plugins": {
    "updater": {
      "endpoints": ["https://github.com/livebook-dev/livebook/releases/latest/download/latest.json"]
    }
  }
}
```

---

## 8. Asset Pipeline

### Stack

- **Bundler:** Bun (v1.3.10 from `config/config.exs` line 21)
- **Builder:** Vite 7 (configured in `assets/vite.config.js`)
- **CSS:** Tailwind CSS 4 (`@tailwindcss/vite` plugin)
- **JS:** Vanilla JS entry (`assets/js/app.js`)
- **Formatter:** Prettier
- **Test runner:** Vitest

### Mix integration

`config/config.exs` line 19-22:
```elixir
config :bun,
  version: "1.3.10",
  assets: [args: ~w(), cd: Path.expand("../assets", __DIR__)]
```

Aliases in `mix.exs` lines 72-79:
```elixir
"assets.setup": ["bun.install --if-missing", "bun assets install", "assets.build"],
"assets.build": ["bun assets run build"],
```

### Vite config highlights

```js
// assets/vite.config.js lines 21-33
build: {
  outDir: "../priv/static",
  emptyOutDir: true,
  rollupOptions: {
    input: "js/app.js",
    output: {
      entryFileNames: `assets/[name].js`,  // No hashes
    },
  },
},
plugins: [
  tailwindcss(),
  compression({ deleteOriginalAssets: true, algorithms: ["gzip"] }),
]
```

- Assets are gzip-compressed **in place** (originals deleted) — critical for escript/desktop bundle size
- No hash in filenames — simplifies asset references
- Copies iframe assets into the build

---

## 9. Dependencies & Version Management

### `versions` file

Single source of truth:
```
elixir="1.20.1"
otp="28.1.1"
rebar3="3.24.0"
ubuntu="noble-20260509.1"
```

Read by CI via `. versions && echo "elixir=$elixir" >> $GITHUB_ENV`.

### Locked deps pattern

`mix.exs` lines 159-178 — reads `mix.lock` and replaces version requirements with locked versions:

```elixir
defp with_lock(deps) do
  for dep <- deps do
    name = elem(dep, 0)
    put_elem(dep, 1, @lock[name] || elem(dep, 1))
  end
end
```

This ensures exact dependency versions in escript and git installs.

---

## 10. Key Patterns Summary

| Pattern | Implementation |
|---------|---------------|
| **Version pinning** | `versions` file sourced in CI, read at build time |
| **Multi-arch Docker** | QEMU + Buildx with `platforms: linux/amd64,linux/arm64` |
| **Docker variants** | Build arg `VARIANT=default|cuda` with CUDA toolkit install |
| **Minimal CI secrets** | Only `TEST_GIT_SSH_KEY` in CI; codesigning secrets in release only |
| **Env var as API** | ~30 typed env vars with validation + sensible defaults |
| **Two release profiles** | Server (lightweight, relies on host Erlang) vs Desktop (bundles OTP+Elixir) |
| **Custom EPMD** | Avoids standard Erlang port mapper for clustering |
| **Auto-clustering** | `LIVEBOOK_CLUSTER=auto` detects Fly.io, ECS, k8s |
| **User extensions** | `RELEASE_ROOT/user/extensions/*.exs` loaded at boot |
| **Desktop boot script** | `~/.livebookdesktop.sh` sourced for user env customization |
| **ElixirKit bridge** | ZeroMQ-based PubSub between Rust (Tauri) and Elixir (BEAM) |
| **Asset compression** | Vite plugin deletes original assets, keeps only `.gz` |
| **No hash in assets** | Deterministic filenames for escript/desktop bundling |
| **Cookie removal** | Release step `remove_cookie/1` prevents cookie sharing across users |
