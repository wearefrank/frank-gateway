#!/usr/bin/env python3
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
# Couldn't find a NLGOV Authzen agent, so this is a basic test data provider. It doesn't need to be perfect, so don't look at it too closely

ALLOWED_PURPOSES = {
    "uitvoering-wettelijke-taak",
    "dienstverlening-burger",
    "fraudepreventie",
}


def _as_dict(value):
    return value if isinstance(value, dict) else {}


def _as_list(value):
    return value if isinstance(value, list) else []


def evaluate(payload):
    # Accept either the OPA-style wrapper {"input": ...} or direct AuthZEN payload.
    req = _as_dict(payload.get("input", payload))

    subject = _as_dict(req.get("subject"))
    subject_properties = _as_dict(subject.get("properties"))
    resource = _as_dict(req.get("resource"))
    resource_properties = _as_dict(resource.get("properties"))
    action_obj = _as_dict(req.get("action"))
    context_obj = _as_dict(req.get("context"))
    context_properties = _as_dict(context_obj.get("properties"))

    purpose = str(context_obj.get("purpose", context_properties.get("purpose", ""))).lower()
    loa = str(
        context_obj.get(
            "loa",
            context_properties.get("loa", subject_properties.get("assurance_level", "")),
        )
    ).lower()
    channel = str(context_obj.get("channel", context_properties.get("channel", ""))).lower()
    action = str(action_obj.get("name", "")).lower()

    roles = _as_list(subject_properties.get("roles"))
    scopes = _as_list(subject_properties.get("scopes"))
    org = str(subject_properties.get("organization", ""))
    sensitivity = str(resource_properties.get("sensitivity", "")).lower()

    required_fields = (
        bool(str(subject.get("type", "")))
        and bool(str(subject.get("id", "")))
        and bool(str(resource.get("type", "")))
        and bool(str(resource.get("id", "")))
        and bool(action)
    )

    organization_ok = org.startswith("urn:nl:gov:")

    resource_type = str(resource.get("type", ""))
    is_citizen_data = resource_type in {"brp-record", "bsn", "citizen-data"}

    allowed_purpose = purpose in ALLOWED_PURPOSES
    loa_ok = loa in {"substantial", "high"}
    mtls_ok = sensitivity != "high" or channel == "mtls"

    role_read_ok = "brp_reader" in roles or "municipality_caseworker" in roles
    role_write_ok = "brp_mutator" in roles or "municipality_caseworker" in roles
    scope_write_ok = "brp:write" in scopes

    action_read_ok = action != "read" or role_read_ok
    action_write_ok = action != "write" or (role_write_ok and scope_write_ok)

    citizen_checks_ok = (not is_citizen_data) or (
        allowed_purpose and loa_ok and mtls_ok and action_read_ok and action_write_ok
    )

    allow = required_fields and organization_ok and citizen_checks_ok

    if not required_fields:
        reason = "Missing required AuthZEN fields (subject.type, subject.id, resource.type, resource.id, action.name)."
    elif not organization_ok:
        reason = "Only subjects from urn:nl:gov organizations are allowed."
    elif is_citizen_data and not allowed_purpose:
        reason = "Requested purpose is not allowed for citizen data processing."
    elif is_citizen_data and allowed_purpose and not loa_ok:
        reason = "Insufficient assurance level for BRP/BSN access."
    elif is_citizen_data and allowed_purpose and loa_ok and not mtls_ok:
        reason = "High sensitivity citizen data requires mTLS transport."
    elif is_citizen_data and allowed_purpose and loa_ok and mtls_ok and action == "read" and not role_read_ok:
        reason = "Missing role for citizen data read."
    elif is_citizen_data and allowed_purpose and loa_ok and mtls_ok and action == "write" and not action_write_ok:
        reason = "Missing role or scope for citizen data write."
    else:
        reason = "Allowed by NL-gov baseline policy."

    if reason == "Missing required AuthZEN fields (subject.type, subject.id, resource.type, resource.id, action.name).":
        reason_user = "Missing required fields in the authorization request."
    elif reason == "Only subjects from urn:nl:gov organizations are allowed.":
        reason_user = "The requesting organization is not allowed for this data."
    elif reason == "Requested purpose is not allowed for citizen data processing.":
        reason_user = "The requested purpose is not allowed for this data."
    elif reason == "Insufficient assurance level for BRP/BSN access.":
        reason_user = "The assurance level is too low for this data access."
    elif reason == "High sensitivity citizen data requires mTLS transport.":
        reason_user = "A secure mTLS channel is required for this resource."
    elif reason == "Missing role for citizen data read.":
        reason_user = "Insufficient role for read access."
    elif reason == "Missing role or scope for citizen data write.":
        reason_user = "Insufficient privileges for write access."
    else:
        reason_user = "Access permitted."

    if allow:
        obligations = ["log_decision"]
    elif is_citizen_data and sensitivity == "high" and not mtls_ok:
        obligations = ["enforce_mtls"]
    else:
        obligations = []

    if reason == "Only subjects from urn:nl:gov organizations are allowed.":
        advice = ["Set subject.properties.organization to urn:nl:gov:<authority>."]
    elif reason == "Requested purpose is not allowed for citizen data processing.":
        advice = ["Use one of: uitvoering-wettelijke-taak, dienstverlening-burger, fraudepreventie."]
    elif reason == "Insufficient assurance level for BRP/BSN access.":
        advice = ["Use loa 'substantial' or 'high'."]
    elif reason == "High sensitivity citizen data requires mTLS transport.":
        advice = ["Set context.properties.channel to 'mtls'."]
    elif reason == "Missing role for citizen data read.":
        advice = ["Grant brp_reader or municipality_caseworker role."]
    elif reason == "Missing role or scope for citizen data write.":
        advice = ["Grant brp_mutator or municipality_caseworker role and include brp:write scope."]
    elif reason == "Missing required AuthZEN fields (subject.type, subject.id, resource.type, resource.id, action.name).":
        advice = ["Add required subject/resource/action fields to the request."]
    else:
        advice = []

    result = {
        "decision": allow,
        "context": {
            "metadata": {
                "policy_id": "nl-gov-authzen-v1",
            },
            "reason_admin": {
                "403": reason,
            },
            "reason_user": {
                "403": reason_user,
            },
            "obligations": obligations,
            "advice": advice,
        },
    }

    return result


class AuthzenHandler(BaseHTTPRequestHandler):
    def _json_response(self, status, body):
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in {"/healthz", "/health", "/"}:
            self._json_response(200, {"status": "ok"})
            return
        self._json_response(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/access/v1/evaluation": 
            self._json_response(404, {"error": "not found"})
            return

        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)

        try:
            payload = json.loads(raw.decode("utf-8") if raw else "{}")
        except json.JSONDecodeError:
            self._json_response(400, {"error": "invalid json"})
            return

        response = evaluate(payload)
        self._json_response(200, response)


def main():
    server = HTTPServer(("0.0.0.0", 8180), AuthzenHandler)
    print("authzen python policy server listening on 0.0.0.0:8180", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
