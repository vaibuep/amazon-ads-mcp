# Deploying Amazon Ads MCP as a claude.ai Custom Connector

This guide takes you from "no server" to a working claude.ai custom
connector, using a free VPS. Steps you do yourself are marked **(you)**.

## 1. Get a free VPS **(you)**

[Oracle Cloud's Always Free tier](https://www.oracle.com/cloud/free/) is the
most practical genuinely-free-forever option — a real, persistent VM with a
public IP (unlike AWS/GCP free tiers, which are free only for 12 months or a
trial credit).

1. Sign up at oracle.com/cloud/free. You'll need an email, phone number, and
   a card for identity verification — the Always Free resources below don't
   get charged.
2. In the console: **Compute → Instances → Create Instance**.
3. Image: **Ubuntu 24.04** (or latest LTS). Shape: click "Change shape" and
   pick an **Always Free eligible** shape — the Ampere `VM.Standard.A1.Flex`
   with 2 OCPUs / 12 GB RAM is comfortable for this server (up to 4
   OCPU/24 GB total is free). If Ampere capacity is unavailable in your
   region, `VM.Standard.E2.1.Micro` (x86, 1 GB RAM) also works but is tight.
4. Under **Add SSH keys**, either paste your own public key
   (`~/.ssh/id_ed25519.pub` from your own machine) or let Oracle generate a
   key pair and download the private key — you'll need it to SSH in.
5. Create the instance and note its **public IP address**.
6. Under the instance's **Subnet → Security List** (or attach a Network
   Security Group), add ingress rules allowing TCP **80** and **443** from
   `0.0.0.0/0`. Port 22 (SSH) is open by default.

> Oracle's Ubuntu images *also* filter inbound traffic with `iptables` on
> the host itself, independent of the console security list. The setup
> script in step 3 opens 80/443 there too, but if requests still time out,
> re-check both layers.

## 2. SSH in **(you)**

```bash
ssh ubuntu@<your-server-public-ip>
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

- Server IP `141.147.1.2` → hostname `141-147-1-2.sslip.io`

If you already own a domain, point an A record at the server's IP instead
and use that hostname.

## 5. Configure `.env` **(you, on the server)**

```bash
cp .env.example .env
nano .env   # or vim/your editor of choice
```

Set these regardless of auth method:

```bash
PUBLIC_HOSTNAME=141-147-1-2.sslip.io     # your hostname from step 4
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
https://141-147-1-2.sslip.io/auth/callback
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
curl -i https://141-147-1-2.sslip.io/mcp \
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
3. Name: "Amazon Ads". URL: `https://141-147-1-2.sslip.io/mcp`.
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
