# AuthZEN NL-gov Policy Agent (Test Setup)

This folder contains an AuthZEN-style NL-gov policy agent based on the standard Open Policy Agent (OPA) container image.

## What you get

- A local policy decision point at `http://localhost:8180/v1/data/authzen/evaluation`.
- NL-gov style policy checks for citizen data access (purpose, LoA, role, scope, mTLS channel).
- Health endpoint: `GET /healthz`.

## Start

Run from this folder (`tests/auth-zen`):

```powershell
docker compose up --build
```

Or only start the policy agent:

```powershell
docker compose up --build authzen-policy-agent
```

## Test requests

Allow example:

```powershell
$body = @'
{
	"input": {
		"subject": {
		"type": "service-account",
		"id": "municipality-case-api",
		"properties": {
			"organization": "urn:nl:gov:rotterdam",
			"assurance_level": "substantial",
			"roles": ["municipality_caseworker"],
			"scopes": ["brp:read"]
		}
		},
		"resource": {
			"type": "brp-record",
			"id": "bsn:999991234",
			"properties": {
				"sensitivity": "high"
			}
		},
		"action": {
			"name": "read"
		},
		"context": {
			"properties": {
				"purpose": "uitvoering-wettelijke-taak",
				"channel": "mtls",
				"loa": "substantial"
			}
		}
	}
}
'@

Invoke-RestMethod -Method Post -Uri http://localhost:8180/v1/data/authzen/evaluation -ContentType 'application/json' -Body $body
```

Deny example (invalid purpose):

```powershell
$body = @'
{
	"input": {
		"subject": {
		"type": "service-account",
		"id": "municipality-case-api",
		"properties": {
			"organization": "urn:nl:gov:rotterdam",
			"assurance_level": "substantial",
			"roles": ["municipality_caseworker"],
			"scopes": ["brp:read"]
		}
		},
		"resource": {
			"type": "brp-record",
			"id": "bsn:999991234",
			"properties": {
				"sensitivity": "high"
			}
		},
		"action": {
			"name": "read"
		},
		"context": {
			"properties": {
				"purpose": "marketing",
				"channel": "mtls",
				"loa": "substantial"
			}
		}
	}
}
'@

Invoke-RestMethod -Method Post -Uri http://localhost:8180/v1/data/authzen/evaluation -ContentType 'application/json' -Body $body
```

## Notes for APISIX plugin testing

- From within the compose network, use `http://authzen-policy-agent:8180/v1/data/authzen/evaluation`.
- Bruno requests are available in `tests/bruno/auth-zen`.
- OPA policy source is `tests/auth-zen/policy-agent/opa/authzen.rego`.