package authzen

import rego.v1

purpose := lower(object.get(input.context.properties, "purpose", ""))
loa := lower(object.get(input.context.properties, "loa", object.get(input.subject.properties, "assurance_level", "")))
channel := lower(object.get(input.context.properties, "channel", ""))
action := lower(object.get(input.action, "name", ""))
roles := object.get(input.subject.properties, "roles", [])
scopes := object.get(input.subject.properties, "scopes", [])
org := object.get(input.subject.properties, "organization", "")
sensitivity := lower(object.get(input.resource.properties, "sensitivity", ""))

allowed_purposes := {
  "uitvoering-wettelijke-taak",
  "dienstverlening-burger",
  "fraudepreventie",
}

required_fields if {
  object.get(input.subject, "id", "") != ""
  object.get(input.resource, "id", "") != ""
  action != ""
}

organization_ok if startswith(org, "urn:nl:gov:")

is_citizen_data if {
  object.get(input.resource, "type", "") == "brp-record"
} else if {
  object.get(input.resource, "type", "") == "bsn"
} else if {
  object.get(input.resource, "type", "") == "citizen-data"
}

allowed_purpose if purpose in allowed_purposes
loa_ok if loa == "substantial"
loa_ok if loa == "high"

mtls_ok if sensitivity != "high"
mtls_ok if channel == "mtls"

role_read_ok if "brp_reader" in roles
role_read_ok if "municipality_caseworker" in roles

role_write_ok if "brp_mutator" in roles
role_write_ok if "municipality_caseworker" in roles

scope_write_ok if "brp:write" in scopes

action_read_ok if action != "read"
action_read_ok if role_read_ok

action_write_ok if action != "write"
action_write_ok if {
  role_write_ok
  scope_write_ok
}

citizen_checks_ok if not is_citizen_data
citizen_checks_ok if {
  is_citizen_data
  allowed_purpose
  loa_ok
  mtls_ok
  action_read_ok
  action_write_ok
}

allow if {
  required_fields
  organization_ok
  citizen_checks_ok
}

reason := "Missing required AuthZEN fields (subject.id, resource.id, action.name)." if {
  not required_fields
} else := "Only subjects from urn:nl:gov organizations are allowed." if {
  required_fields
  not organization_ok
} else := "Requested purpose is not allowed for citizen data processing." if {
  required_fields
  organization_ok
  is_citizen_data
  not allowed_purpose
} else := "Insufficient assurance level for BRP/BSN access." if {
  required_fields
  organization_ok
  is_citizen_data
  allowed_purpose
  not loa_ok
} else := "High sensitivity citizen data requires mTLS transport." if {
  required_fields
  organization_ok
  is_citizen_data
  allowed_purpose
  loa_ok
  not mtls_ok
} else := "Missing role for citizen data read." if {
  required_fields
  organization_ok
  is_citizen_data
  allowed_purpose
  loa_ok
  mtls_ok
  action == "read"
  not role_read_ok
} else := "Missing role or scope for citizen data write." if {
  required_fields
  organization_ok
  is_citizen_data
  allowed_purpose
  loa_ok
  mtls_ok
  action == "write"
  not action_write_ok
} else := "Allowed by NL-gov baseline policy."

obligations := ["log_decision"] if allow
obligations := ["enforce_mtls"] if {
  not allow
  is_citizen_data
  sensitivity == "high"
  not mtls_ok
}
obligations := [] if {
  not allow
  not is_citizen_data
}
obligations := [] if {
  not allow
  is_citizen_data
  sensitivity != "high"
}
obligations := [] if {
  not allow
  is_citizen_data
  sensitivity == "high"
  mtls_ok
}

advice := ["Set subject.properties.organization to urn:nl:gov:<authority>."] if {
  reason == "Only subjects from urn:nl:gov organizations are allowed."
}
advice := ["Use one of: uitvoering-wettelijke-taak, dienstverlening-burger, fraudepreventie."] if {
  reason == "Requested purpose is not allowed for citizen data processing."
}
advice := ["Use loa 'substantial' or 'high'."] if {
  reason == "Insufficient assurance level for BRP/BSN access."
}
advice := ["Set context.properties.channel to 'mtls'."] if {
  reason == "High sensitivity citizen data requires mTLS transport."
}
advice := ["Grant brp_reader or municipality_caseworker role."] if {
  reason == "Missing role for citizen data read."
}
advice := ["Grant brp_mutator or municipality_caseworker role and include brp:write scope."] if {
  reason == "Missing role or scope for citizen data write."
}
advice := ["Add required subject/resource/action fields to the request."] if {
  reason == "Missing required AuthZEN fields (subject.id, resource.id, action.name)."
}
advice := [] if {
  reason == "Allowed by NL-gov baseline policy."
}

evaluation := {
  "policy_id": "nl-gov-authzen-v1",
  "decision": allow,
  "reason": reason,
  "obligations": obligations,
  "advice": advice,
}
