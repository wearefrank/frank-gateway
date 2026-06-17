package apisix.authz

# Example OPA policy document consumed by APISIX at /v1/data/apisix/authz/result
# Allow only when request body includes {"allow": true}.
default result := {
  "allow": false,
  "status_code": 403,
  "reason": "access denied: request body must include allow=true"
}

result := {
  "allow": true,
  "headers": {
    "x-opa-user": subject
  }
} {
  body := object.get(input.request, "body", {})
  is_object(body)
  body.allow == true
  subject := object.get(body, "subject", "demo-user")
}
