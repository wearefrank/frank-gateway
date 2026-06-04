package doelbinding.subsidies

import rego.v1

# Default path used when no rvva-id or doelbinding header/attribute is present.
# The OPA controller routes to /authz in that case.
# For doelbinding-scoped policies use: package doelbinding.<name>
# For activity-scoped policies use:    package activity.<rvva-id>

default allow := false
