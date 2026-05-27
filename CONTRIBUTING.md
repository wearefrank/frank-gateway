# Contributing

This project uses:

* Conventional Commits
* Semantic Versioning
* semantic-release
* Automated GitHub Releases
* Automated Docker Publishing

Please read this document before opening a Pull Request.

---

# Branching Strategy

The primary development branch is:

master

Unless instructed otherwise, all Pull Requests should target the `master` branch.

---

# Release Automation

Releases are fully automated using `semantic-release`.

Versions are calculated automatically based on Pull Request titles.

Do NOT manually:

* Create Git tags
* Create GitHub releases
* Modify release versions

The CI/CD pipeline handles this automatically after merge.

---

# Pull Request Titles

This repository uses Conventional Commits through Pull Request titles.

The final squash merge commit is generated from the PR title and used by `semantic-release`.

PR titles must follow this format:

<type>(optional-scope): description

Examples:

feat(api): add OAuth2 support
fix(auth): resolve JWT refresh issue
perf(cache): improve Redis lookup performance
docs(readme): update installation instructions

---

# Release Types

The following PR title types create releases:

| Type   | Release |
| ------ | ------- |
| feat   | Minor   |
| fix    | Patch   |
| perf   | Patch   |
| revert | Patch   |

Examples:

feat(api): add OAuth support

Produces:

1.4.0 -> 1.5.0

---

fix(auth): resolve token refresh bug

Produces:

1.5.0 -> 1.5.1

---

# Breaking Changes

Breaking changes create a major release.

You can indicate a breaking change in two ways.

## Method 1 — Use !

feat!: remove legacy SOAP endpoints

## Method 2 — BREAKING CHANGE footer

feat(api): redesign authentication system

BREAKING CHANGE: legacy authentication endpoints were removed

Produces:

1.x.x -> 2.0.0

---

# Non-Release Types

The following PR title types do NOT create releases:

* docs
* test
* ci
* chore

Examples:

docs(readme): fix typo
ci(github): update workflow permissions
test(api): improve integration coverage

These changes will not publish a new Docker image or GitHub release.

---

# Commit Messages

Commit messages inside a Pull Request are not important for versionin, however please make sure to make your commits descriptive and targeted.

The squash merge commit generated from the PR title is what drives releases.

---

# Squash Merging

This repository uses squash merging exclusively.

Before merging, ensure the Pull Request title follows the Conventional Commits format.

Good examples:

feat(api): add OAuth2 support
fix(cache): resolve Redis connection leak

Bad examples:

Update stuff
Fix things
Changes

---

# Pull Request Guidelines

Please:

* Keep Pull Requests focused
* Prefer one logical change per PR
* Add tests where appropriate
* Update documentation when needed
* Ensure CI passes before requesting review

Good example:

fix(auth): resolve JWT expiration handling

Bad example:

feat: add auth, update docs, fix CI, and refactor cache

---



## Testing
For a more detailed explaination about the testing requirements for developping plugins, make sure to check out the readme under src/plugins

### Unit testing plugins

Plugin logic is tested with [Busted](https://lunarmodules.github.io/busted/), a Lua unit testing framework, running inside a minimal Docker container. All spec files live in the `spec/` folder at the repository root alongside a shared `Dockerfile` that sets up the test runner.


---

### Postman tests
For manual API validation you can use the collection in `tests/bruno/bruno.json` (with suite requests under `tests/bruno/*`).

### Local test run (all suites)
For local automated testing across all plugin suites, run:

```bat
run-all-tests.bat
```

This script starts each test suite environment, executes the Bruno tests, and writes JUnit reports to `tests/bruno/results`.

### FSC 
The FSC plugin:
- Can act as a Inway in a FSC NLX group
- Can combine the FSC NLX Inway with different APISIX plugins 

Detailed documentation on the FSC plugin and how to run and test the FSC plugin locally can be found [here](tests/fsc/FSC-NLX.md)

### SOAP action router
APISIX can create routing rules based on HTTP headers. However, within SOAP the specific operation is determined by the SOAP action, this SOAP action can either be in a HTTP header, Content-Type header or body.
The plugin can extract the SOAP action and trigger the router enabling the possibility to create routes per SOAP action.

Detailed documentation on the SOAP action router and Postman test collection can be found [here](deployment-examples/docker-compose/README.md)

### OIDC client
APISIX has existing OpenID connect and JWT plugins, but these plugins are for protecting routes. In these plugins the clients of APISIX need to authenticate and APISIX checks the access tokens.
The OIDC client plugin enables the Frank!Gateway to a OIDC client that can authenticate with a external IDP and use the client_credentials flow to authenticate with a upstream.

Detailed documentation on the OIDC client can be found here [here](deployment-examples/oidc-client/OIDC-client.md)

### Generic OAuth client
A flexible and custom version of the OIDC client plugin allowing you to define your own fields. 

Detailed documentation on the Generic OAuth Client plugin can be found here [here](docs/generic-oauth-plugin/readme.md)


### Limit size
blocks either requests and or responses if the payload or entire request or response is larger than a pre-configured threshold.

### Response extractor
Extracts values from upstream JSON response bodies using [JSONPath](https://goessner.net/articles/JsonPath/) expressions and exposes them as APISIX request context variables for use by downstream plugins or log formats.

The plugin is configured as a map of variable name → JSONPath expression. Each matched value is:
- Stored in `ctx.extracted` (a Lua table, accessible by other plugins in the same request)
- Stored as `ctx.var.extracted` (a JSON-encoded string, usable in `log_format`)
- Stored individually as `ctx.var.<variable_name>` for direct access in log formats or other plugins

Example configuration:
```yaml
response-extractor:
  transaction_id: "$.transactionId"
  status_code: "$.result.status"
```

This would make `$transaction_id` and `$status_code` available as APISIX variables for logging or further processing.

> **Note:** The plugin only processes JSON responses (`application/json` or `+json`). Responses without a JSON body are silently skipped. The extractor buffers up to 1 MB of response body; larger responses are skipped to protect memory usage.

### Cert Auth 

APISIX supports TLS, but by default this is mainly used for server-side TLS termination.
The Cert Auth plugin enables mutual TLS (mTLS) client authentication, allowing APISIX to identify consumers based on certificate attributes such as Common Name (CN) or SAN identifier.

Detailed documentation on the Cert Auth plugin and local setup can be found [here](docs/cert-auth-plugin/README.MD).

### Frank Sender 

The Frank Sender plugin forwards the incoming request to a configured Frank endpoint first, reads the response body, and replaces the original in-flight request body with that response before continuing to the configured upstream.
This enables request transformation and mapping logic to be centralized in a Frank service.

Detailed documentation on the Frank Sender plugin can be found [here](docs/frank-sender/README.md).

### Jwt Client 

APISIX has existing authentication plugins for validating incoming tokens, but this plugin is focused on outbound authentication.
The JWT Client plugin enables the Frank!Gateway to request a JWT access token from an external IDP, cache it, and add it as a Bearer token on upstream requests.

Example configuration and tests for the JWT Client plugin can be found [here](tests/jwt-client/apisix.yaml) and [here](tests/bruno/jwt-client).


# CI/CD Flow

After merging into `master`:

1. CI runs automatically
2. semantic-release analyzes the squash commit
3. A new version is calculated
4. The changelog is updated
5. A GitHub Release is created
6. Docker images are published automatically

---

# Thank You

Thank you for contributing 🚀
