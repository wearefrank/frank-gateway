#!/usr/bin/env python3
"""
traffic_sender_auth.py

Sends an initial request to http://localhost:9080/any and, once it responds,
fires additional concurrent requests to configured routes — each with its own
Basic Authentication credentials.

Requirements:
    pip install aiohttp
"""

import asyncio
import aiohttp
import random
import time
from typing import Tuple, Optional

# -----------------------
# Configuration section
# -----------------------
BASE = "http://localhost:9080"
INITIAL_PATH = "/any"

# Each route can specify:
# - path (string)
# - method ("GET"/"POST")
# - auth (tuple[str, str]) for Basic Auth
# - body (dict) optional for POST
ROUTES = [
    {
        "path": "/any/users",
        "method": "GET",
        "auth": ("user1", "pass1"),
    },
    {
        "path": "/any/orders",
        "method": "POST",
        "auth": ("user2", "pass2"),
        "body": {"event": "ping"},
    },
    {
        "path": "/any/products",
        "method": "POST",
        "auth": ("admin", "secret123"),
        "body": {"value": 42},
    },
    {
        "path": "/any/documents",
        "method": "GET",
        "auth": ("admin", "secret123"),
    },
    {
        "path": "/any/health",
        "method": "GET",
        "auth": ("user1", "pass1"),
    },
    {
        "path": "/any/metrics",
        "method": "GET",
        "auth": ("admin", "secret123"),
    },
    {
        "path": "/any/status",
        "method": "GET",
        "auth": ("user2", "pass2"),
    },
    {
        "path": "/any/login",
        "method": "POST",
        "auth": ("user1", "pass1"),
        "body": {"login": True},
    },
    {
        "path": "/any/logout",
        "method": "POST",
        "auth": ("user2", "pass2"),
        "body": {"logout": True},
    },
]

DEFAULT_HEADERS = {
    "User-Agent": "traffic-sender/1.1",
    "Accept": "application/json",
}

MAX_CONCURRENCY = 10
MAX_RETRIES = 3
RETRY_BASE_DELAY = 0.5  # seconds

# -----------------------
# Helper functions
# -----------------------
def backoff_delay(attempt: int) -> float:
    base = RETRY_BASE_DELAY * (2 ** (attempt - 1))
    jitter = random.uniform(0, base * 0.5)
    return base + jitter

async def safe_read(resp: aiohttp.ClientResponse):
    """Try to read JSON, else text, with safe exception handling."""
    try:
        return await resp.json()
    except Exception:
        try:
            return await resp.text()
        except Exception as e:
            return f"<unreadable: {e}>"

# -----------------------
# Core async logic
# -----------------------
async def fetch_initial(session: aiohttp.ClientSession):
    url = BASE + INITIAL_PATH
    print(f"[+] Sending initial request -> {url}")
    try:
        async with session.get(url, headers=DEFAULT_HEADERS, timeout=10) as resp:
            text = await resp.text()
            print(f"[+] Initial response: {resp.status} ({len(text)} bytes)")
            try:
                j = await resp.json()
            except Exception:
                j = {"raw_text": text}
            return {"status": resp.status, "json": j}
    except Exception as e:
        print(f"[-] Initial request failed: {e}")
        raise

async def send_one(
    session: aiohttp.ClientSession,
    path: str,
    method: str = "GET",
    auth: Optional[Tuple[str, str]] = None,
    body: Optional[dict] = None,
    sem: Optional[asyncio.Semaphore] = None,
):
    url = path if path.startswith("http") else BASE + path
    attempt = 0
    async with sem:
        while attempt < MAX_RETRIES:
            attempt += 1
            try:
                if method.upper() == "GET":
                    async with session.get(
                        url,
                        headers=DEFAULT_HEADERS,
                        auth=aiohttp.BasicAuth(*auth) if auth else None,
                        timeout=10,
                    ) as r:
                        data = await safe_read(r)
                        print(f"[>] GET {url} -> {r.status}")
                        return {"url": url, "status": r.status, "body": data}
                else:
                    payload = (body or {}).copy()
                    payload["ts"] = time.time()
                    async with session.post(
                        url,
                        headers={**DEFAULT_HEADERS, "Content-Type": "application/json"},
                        auth=aiohttp.BasicAuth(*auth) if auth else None,
                        json=payload,
                        timeout=10,
                    ) as r:
                        data = await safe_read(r)
                        print(f"[>] POST {url} -> {r.status}")
                        return {"url": url, "status": r.status, "body": data}
            except Exception as e:
                delay = backoff_delay(attempt)
                print(f"[*] Attempt {attempt} for {url} failed: {e} — retrying in {delay:.2f}s")
                await asyncio.sleep(delay)

        print(f"[-] Exhausted retries for {url}")
        return {"url": url, "status": None, "body": None, "error": "retries_exhausted"}

async def main():
    connector = aiohttp.TCPConnector(limit_per_host=MAX_CONCURRENCY)
    timeout = aiohttp.ClientTimeout(total=30)
    sem = asyncio.Semaphore(MAX_CONCURRENCY)
    async with aiohttp.ClientSession(connector=connector, timeout=timeout) as session:
        # Initial request
        try:
            initial = await fetch_initial(session)
        except Exception:
            print("Initial request failed — aborting follow-ups.")
            return

        # Follow-up requests
        tasks = [
            asyncio.create_task(send_one(session, r["path"], r.get("method", "GET"), r.get("auth"), r.get("body"), sem))
            for r in ROUTES
        ]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        print("\n--- Follow-up Summary ---")
        for r in results:
            if isinstance(r, Exception):
                print(f"Exception in task: {r}")
            else:
                print(f"{r['url']} -> {r['status']}")
        print("-------------------------\n")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Interrupted by user")
