# Third-party image mirrors

Images that are unreliable or temporary at their upstream registry can be copied to this repository owner's GitHub Container Registry (GHCR) namespace. The mirror keeps a version available for CI and local development even if the upstream image is later removed.

## Add a mirror

Create a directory under `mirrors/` named for the image, and add a `Dockerfile` containing a single tagged upstream image:

```dockerfile
FROM registry.example.com/team/image:v1.2.3
```

For example, `mirrors/open-ftv-pdp/Dockerfile` currently tracks the Open FTV PDP image. Use a tag rather than a digest: the workflow derives the mirrored tag from the `FROM` reference. Keep the Dockerfile to this simple `FROM` form; the workflow reads its first `FROM` line and copies that image without rebuilding it.

The `Mirror third-party images` workflow publishes the image as:

```text
ghcr.io/<repository-owner>/mirror-<directory-name>:<upstream-tag>
```

It runs when changes under `mirrors/` reach `main` or `master`. It can also be started manually from the Actions tab. The workflow copies all configured mirrors on each run.

After the first publish, set the GHCR package visibility to **Public** in the package settings if CI and developers should pull it without authenticating. The first mirror must be published before a compose file that references it is used.

## Use a mirror

Reference the GHCR image in the relevant `docker-compose.yaml` using the generated name and tag, for example:

```yaml
image: ghcr.io/wearefrank/mirror-open-ftv-pdp:v0.1.0
```

For private packages, configure Docker authentication to GHCR in both CI and local development. Public packages can be pulled directly by Docker Compose.

## Keep mirrors up to date

Dependabot checks the Dockerfiles under `mirrors/*` weekly and can open a PR with an available upstream tag update. When reviewing such a PR:

1. Confirm the proposed upstream tag is the intended version.
2. Update every compose file that uses this mirror to the matching mirrored tag. Dependabot does not update those compose references.
3. Merge the PR. The push to `main` or `master` triggers the mirror workflow, which publishes the new tag to GHCR.
4. Ensure the workflow succeeds before relying on the new tag in CI or local compose.

The old GHCR tag remains available, so existing compose configurations continue to work. For a newly added mirror, publish it first (by merging the mirror definition and running the workflow, or using `workflow_dispatch`) before merging or running configurations that depend on it.