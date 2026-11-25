const crypto = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");
const https = require("node:https");

let tokenRequests = 0;
const seenAssertions = new Set();
const audience = "https://mock-idp:8443/token?tenant=test";

https.createServer({
  key: fs.readFileSync("/fixtures/test/tls-key.pem"),
  cert: fs.readFileSync("/fixtures/test/tls-cert.pem"),
}, async (req, res) => {
  try {
    tokenRequests++;
    let body = "";
    for await (const chunk of req) body += chunk;
    const form = new URLSearchParams(body);
    if (req.url !== "/token?tenant=test" || req.method !== "POST" ||
        req.headers["content-type"] !== "application/x-www-form-urlencoded" ||
        form.get("grant_type") !== "client_credentials" ||
        form.get("client_id") !== "test-client" ||
        form.get("scope") !== "read test" ||
        form.get("client_assertion_type") !== "urn:ietf:params:oauth:client-assertion-type:jwt-bearer") {
      throw new Error("invalid token request");
    }

    const jwksResponse = await fetch("http://apisix:9080/private-key-jwt/jwks");
    if (!jwksResponse.ok) throw new Error("JWKS unavailable");
    const jwks = await jwksResponse.json();
    const assertion = form.get("client_assertion");
    const parts = assertion && assertion.split(".");
    if (!parts || parts.length !== 3) throw new Error("invalid assertion");
    const header = JSON.parse(Buffer.from(parts[0], "base64url"));
    const claims = JSON.parse(Buffer.from(parts[1], "base64url"));
    const publicKey = jwks.keys.find((key) => key.kid === header.kid);
    if (!publicKey || header.alg !== "RS256" || header.typ !== "JWT" ||
        claims.iss !== "test-client" || claims.sub !== "test-client" ||
        claims.aud !== audience || claims.exp - claims.iat !== 60 ||
        claims.exp <= Date.now() / 1000 || typeof claims.jti !== "string" ||
        seenAssertions.has(claims.jti) ||
        !crypto.verify("RSA-SHA256", Buffer.from(parts[0] + "." + parts[1]),
          crypto.createPublicKey({key: publicKey, format: "jwk"}), Buffer.from(parts[2], "base64url"))) {
      throw new Error("invalid signed assertion");
    }
    seenAssertions.add(claims.jti);
    res.writeHead(200, {"Content-Type": "application/json"});
    res.end(JSON.stringify({access_token: "test-access-token", token_type: "Bearer", expires_in: 120}));
  } catch (error) {
    console.error("Token request rejected:", error.message);
    res.writeHead(401, {"Content-Type": "application/json"});
    res.end(JSON.stringify({error: "invalid_client"}));
  }
}).listen(8443, "0.0.0.0");

http.createServer((req, res) => {
  res.writeHead(200, {"Content-Type": "application/json"});
  res.end(JSON.stringify({
    authorization: req.headers.authorization,
    token_requests: tokenRequests,
  }));
}).listen(8080, "0.0.0.0");
