from flask import Flask, request, jsonify
import jwt
from datetime import datetime, timedelta, timezone

app = Flask(__name__)

# Dummy client credentials
VALID_CLIENT_ID = "jwt_client_id"
VALID_CLIENT_SECRET = "jwt_client_secret"
JWT_SECRET = "my-signing-secret"

@app.route("/token", methods=["POST"])
def token():
    if not request.is_json:
        return jsonify(error="invalid_request", error_description="Content-Type must be application/json"), 400

    data = request.get_json()
    client_id = data.get("client_id")
    client_secret = data.get("client_secret")
    grant_type = data.get("grant_type")

    if grant_type != "client_credentials":
        return jsonify(error="unsupported_grant_type"), 400

    if client_id != VALID_CLIENT_ID or client_secret != VALID_CLIENT_SECRET:
        return jsonify(error="invalid_credentials"), 401

    # Generate JWT access token
    now = datetime.now(timezone.utc)
    exp = now + timedelta(hours=1)
    payload = {
        "sub": client_id,
        "iat": now.timestamp(),
        "exp": exp.timestamp(),
        "scope": "read write"
    }

    access_token = jwt.encode(payload, JWT_SECRET, algorithm="HS256")

    return jsonify({
        "access_token": access_token,
        "token_type": "Bearer",
        "expires_in": 3600
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
