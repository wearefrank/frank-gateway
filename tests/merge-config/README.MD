# Merge-config test suite

## Overview

This test suite verifies the `scripts/merge.lua` configuration merge script.

The merge script watches `conf/mergeconfigs/` for YAML files, merges their
APISIX sections (routes, upstreams, consumers, …) into a single
`conf/apisix.yaml`, and re-runs every 2 seconds when a file changes.

### Test fixtures (`mergeconfigs/`)

| File | Purpose |
|------|---------|
| `config1.yaml` | Defines the shared `httpbun` upstream and a route on `/from-config1` |
| `config2.yaml` | Defines a second route on `/from-config2` that reuses the upstream from config1 |

APISIX is configured with `MERGE_CONFIGURATIONS=true`, so the merge script
runs automatically in the background when the container starts.

## Quick start

Build the Frank Gateway image from the repository root (only needed once or after code changes):

```shell
docker build -t frank-gateway:local .
```

Start the merge-config test stack:

```shell
cd tests/merge-config
docker compose up -d --build --force-recreate
```

## Bruno tests

The Bruno collection lives in `tests/bruno/merge-config`.

Run manually with Bruno CLI:

```shell
docker run --rm \
  --network frank-gateway-merge-config-tests_apisix \
  --add-host host.docker.internal:<apisix-container-ip> \
  -v $(pwd):/workspace \
  -w /workspace/tests/bruno/merge-config \
  alpine/bruno run . -r --env docker
```

Or use `run-all-tests.bat` from the repository root to run all suites
including merge-config automatically.

### Tests

| File | Scenario | Expected |
|------|----------|----------|
| `01-route-from-config1-200.bru` | `GET /from-config1` | 200 – route defined in config1 is reachable |
| `02-route-from-config2-200.bru` | `GET /from-config2` | 200 – route defined in config2 is reachable |
| `03-unknown-route-404.bru` | `GET /not-a-route` | 404 – undefined path is rejected |

## Standalone script test

`test-only-script.yaml` runs the merge script in isolation (no APISIX) and
writes the merged output to `output/apisix.yaml`.  Useful for inspecting the
merge result without standing up the full stack:

```shell
docker compose -f tests/merge-config/test-only-script.yaml up --build
```

The generated file is written to `tests/merge-config/output/apisix.yaml`.

