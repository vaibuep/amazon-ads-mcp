# Deploying Amazon Ads MCP as a claude.ai Custom Connector

This guide takes you from "no server" to a working claude.ai custom
connector, using a free VPS. Steps you do yourself are marked **(you)**.

## 1. Get a free VPS **(you)**

[Google Cloud's Always Free tier](https://cloud.google.com/free) includes
one `e2-micro` instance per billing account, permanently free (not a
time-limited trial), as long as it stays in an eligible US region.

1. Sign up / sign in at [console.cloud.google.com](https://console.cloud.google.com).
   You'll need a card on file for identity verification — Always Free
   resources within the limits below don't get charged.
2. Create (or select) a project.
3. **Compute Engine → VM instances → Create Instance**.
4. **Region**: pick one of the free-eligible regions — `us-west1`,
   `us-central1`, or `us-east1` (any zone within them). Other regions incur
   charges.
5. **Machine type**: `e2-micro` (2 vCPU shared-core, **1 GB RAM** — this is
   the free-tier limit, so the setup script below adds swap to compensate).
6. **Boot disk**: Ubuntu 24.04 LTS, and make sure the disk type is
   **Standard persistent disk** (not SSD/balanced) at 30 GB or less — that's
   what's covered by Always Free.
7. **Firewall**: tick both **"Allow HTTP traffic"** and **"Allow HTTPS
   traffic"** checkboxes. This auto-creates the `default-allow-http` /
   `default-allow-https` VPC firewall rules and tags the instance, so 80/443
   are reachable without extra console steps.
8. Create the instance and note its **external (public) IP address**.

> If you instead create the instance via `gcloud` CLI or Terraform rather
> than the checkboxes above, you'll need to create the equivalent firewall
> rules yourself (`gcloud compute firewall-rules create --allow=tcp:80,tcp:443 ...`).

## 2. SSH in **(you)**

Easiest: in the console, click the **SSH** button next to your instance —
it opens a browser-based terminal, no key management needed.

Alternatively, from your own machine with the [gcloud CLI](https://cloud.google.com/sdk/docs/install):

```bash
gcloud compute ssh <instance-name> --zone=<zone>
```

## 3. Run the setup script **(you, on the server)**

```bash
curl -fsSL https://raw.githubusercontent.com/vaibuep/amazon-ads-mcp/claude/amazon-ads-mcp-connector-bnxcy2/deploy/setup-server.sh | bash
```

This installs Docker + Compose, opens 80/443 on the host firewall, and
clones this repo to `~/amazon-ads-mcp`. Log out and back in once (for the
`docker` group membership to apply), then:

```bash
cd ~/amazon-ads-mcp
```

## 4. Pick a hostname **(you)**

claude.ai needs a real HTTPS hostname (not a bare IP) so Caddy can obtain a
Let's Encrypt certificate. If you don't want to buy a domain, use
[sslip.io](https://sslip.io) — it resolves `<ip-with-dashes>.sslip.io` to
that IP automatically, no DNS setup needed:

- Server IP `34.123.45.67` → hostname `34-123-45-67.sslip.io`

If you already own a domain, point an A record at the server's IP instead
and use that hostname.

## 5. Configure `.env` **(you, on the server)**

```bash
cp .env.example .env
nano .env   # or vim/your editor of choice
```

Set these regardless of auth method:

```bash
PUBLIC_HOSTNAME=34-123-45-67.sslip.io     # your hostname from step 4
PORT=9080
```

Generate a strong inbound token — this is what protects your server from
being called by anyone who finds the URL (required for any public
deployment; see `src/amazon_ads_mcp/server/inbound_auth.py`):

```bash
openssl rand -hex 32
```

Put the result in `.env`:

```bash
MCP_INBOUND_TOKEN=<paste the 64-char hex string here>
```

Then set **one** of the three auth blocks below, matching the credentials
you have:

<details>
<summary><b>Direct (BYOA)</b> — your own Login with Amazon app</summary>

```bash
AUTH_METHOD=direct
AMAZON_AD_API_CLIENT_ID=amzn1.application-oa2-client.xxxxx
AMAZON_AD_API_CLIENT_SECRET=xxxxxxxxxxxxxxxx
# AMAZON_AD_API_REFRESH_TOKEN=...   # optional; otherwise use start_oauth_flow at runtime
```

In the [Amazon Developer Console](https://developer.amazon.com/), set your
app's "Allowed Return URLs" to:

```
https://34-123-45-67.sslip.io/auth/callback
```

(swap in your real hostname from step 4).
</details>

<details>
<summary><b>Openbridge</b> — partner-managed auth</summary>

```bash
AUTH_METHOD=openbridge
OPENBRIDGE_REFRESH_TOKEN=xxxxxx
```
</details>

<details>
<summary><b>Kuudo</b> — org-managed credential vending</summary>

```bash
AUTH_METHOD=kuudo
KUUDO_API_BASE_URL=https://amazon-spapi-dev.kuudo.ai/
KUUDO_API_KEY=sk_xxxxxx
KUUDO_PROVIDER=amazon_ads
```
</details>

## 6. Start the server **(you, on the server)**

```bash
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml up -d --build
docker compose logs -f amazon-ads-mcp   # Ctrl-C once it looks healthy
```

`docker-compose.prod.yaml` adds a Caddy reverse proxy that terminates TLS
and forwards to the app; the app itself is bound to `127.0.0.1` only, so
Caddy is the sole public entrypoint.

## 7. Verify **(you)**

```bash
curl -i https://34-123-45-67.sslip.io/mcp \
  -H "Authorization: Bearer <your MCP_INBOUND_TOKEN>" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"0"}}}'
```

A JSON-RPC response (not a connection error or TLS error) means the server
and certificate are working.

## 8. Add the connector in claude.ai **(you)**

1. [claude.ai](https://claude.ai) → profile icon → **Settings** → **Connectors**.
2. **Add custom connector**.
3. Name: "Amazon Ads". URL: `https://34-123-45-67.sslip.io/mcp`.
4. Authentication: **Bearer token**, value = your `MCP_INBOUND_TOKEN`.
5. Save. claude.ai validates the connection; the Amazon Ads tools become
   available in chats where you enable this connector.

If you used `AUTH_METHOD=direct` without a pre-set refresh token, ask
Claude (in a chat with the connector enabled) to *"start my OAuth flow"* —
it'll walk you through linking your Amazon Ads account the first time.

## Updating later

```bash
cd ~/amazon-ads-mcp
git pull origin claude/amazon-ads-mcp-connector-bnxcy2
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml up -d --build
```
