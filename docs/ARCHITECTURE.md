# Architecture

This document describes the architecture and installation scenarios supported by the remnawave-installer.

## Installation Scenarios

### Option 1: Two Servers (Panel and Node separately)

Recommended for better reliability and flexibility.

**Panel Server:**
- Remnawave Panel
- Subscription-Page
- Angie (for panel and subscriptions)
- PostgreSQL, Redis

**Node Server:**
- Remnawave Node (with Xray)
- Angie for Selfsteal domain

**DNS Configuration:**
- Panel and Subscription domains → Panel server IP
- Selfsteal domain → Node server IP

**Installation Order:**
1. On Panel server: select "Panel Only". Save the public key (`SSL_CERT="..."`)
2. On Node server: select "Node only". Enter selfsteal domain, panel IP, and the saved public key

### Option 2: All-in-One (Panel and Node on one server)

Simplified option, suitable for testing or small loads.

**One server contains:**
- Remnawave Panel, Node, Subscription-Page
- Angie, PostgreSQL, Redis

**DNS:** All three domains (different!) → IP of this single server

### Traffic Routing (All-in-One mode)

```
Client → Port 443 → Xray (local Remnawave Node)
                      ├─ (VLESS proxy traffic) → Processed by Xray
                      └─ (Non-VLESS traffic, fallback) → Angie (127.0.0.1:9443, plain TLS)
                                                          ├─ SNI: Panel Domain → Remnawave Panel (port 3000)
                                                          ├─ SNI: Subscription Domain → Subscription Page (port 3010)
                                                          └─ SNI: Selfsteal Domain → 403 Forbidden
```

> **Note**: Xray passes connections to Angie without the PROXY protocol (`xver: 0`), so behind Xray the panel and subscription page see `127.0.0.1` as the client address.

> **Note**: In All-in-One mode, if you stop the local Remnawave Node or break the Xray config, the panel and other web services will become inaccessible through domain names.

## Directory Structure

### Panel Installation (`/opt/remnawave/`)
```
/opt/remnawave/
├── .env                    # Panel environment
├── docker-compose.yml      # Panel services
├── credentials.txt         # Generated credentials
├── Makefile                # Service management
├── angie/
│   ├── angie.conf         # Base configuration
│   ├── conf.d/            # ACME clients, server blocks, panel auth
│   ├── snippets/          # Error responses and locations
│   └── docker-compose.yml
├── subscription-page/
│   └── docker-compose.yml
└── node/                   # (All-in-One only)
    ├── .env
    └── docker-compose.yml
```

### Separate Node Installation (`/opt/remnanode/`)
```
/opt/remnanode/
├── .env
├── docker-compose.yml
├── Makefile
└── selfsteal/
    ├── angie.conf
    ├── conf.d/
    ├── snippets/
    └── docker-compose.yml
```

## Panel Access Protection

### Secret link (403)
- Access via URL with secret key: `https://panel.example.com/auth/login?<random name>=<secret>`
- Angie sets a cookie on first visit
- Without a valid cookie or parameter, every path returns `403 Forbidden`

### Basic Auth (401, recommended)
- **Two-level authentication:**
  1. HTTP Basic Auth in Angie (the browser's own credentials dialog, no MFA)
  2. Remnawave Panel login
- Without credentials, every path returns `401 Authorization Required`
- After a successful login Angie sets a session cookie, because the panel UI uses the `Authorization` header for its own API tokens
- External API clients must send the session cookie from a browser or connect locally to port 3000

### Certificates
- Angie's built-in ACME module requests a separate Let's Encrypt certificate for each domain over HTTP-01 and renews it 30 days before expiry, no cron or restart needed
- Port 80 must be reachable from the internet, also for renewals. Validation does not pass through Xray and does not need it to be running. Angie also listens on IPv6 if the host has it
- Certificates are stored in the `remnawave-angie-acme` Docker volume; `--keep-angie-data` preserves it during reinstall
- Installations made with the Caddy-based version must be reinstalled: the Xray fallback target has changed

## Network Configuration

### Open Ports
| Port | Purpose |
|------|---------|
| 80/tcp | Angie HTTP, ACME validation |
| 443/tcp | Angie HTTPS / Xray |
| 22/tcp | SSH (or your custom port) |
| 2222/tcp | Node API (restricted) |

### Port 2222 Restrictions
- **All-in-One**: Open only for 172.30.0.0/16 (Docker subnet)
- **Separate Node**: Open only for panel IP
