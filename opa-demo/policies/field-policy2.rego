package apisix.authz.v2

import rego.v1

default allow := false
###########################
# Normalize and clean requested fields
###########################
requested_fields := { f | some f in input.request.body.fields }

version := 2.0

# Normalize allowed fields
allowed_fields_set := { f | some f in data.allowed_fields }
###########################
# Prefix matching logic
###########################
# A requested field is allowed if:
# - exact match
# - OR it is a subfield of an allowed field (prefix + ".")
is_allowed_field(r) if {
    a := allowed_fields_set[_]
    r == a
} 

is_allowed_field(r) if {
    a := allowed_fields_set[_]
    startswith(r, concat(".", [a, ""]))
    # equivalent to startswith(r, a + ".")
}

###########################
# Denied fields = those that do NOT match prefix logic
###########################
denied_fields := { r | some r in requested_fields; not is_allowed_field(r) }

###########################
# Allow only if no denied fields exist
###########################
allow if count(denied_fields) == 0