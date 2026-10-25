# autovpn

Spin up an on-demand OpenVPN endpoint on EC2 (~1 min) and run a torrent stack through it in Docker:

* **gluetun** – VPN client + firewall kill switch; all other containers share its network,
  so nothing (downloads, searches, DNS) can leave except through the EC2 tunnel
* **qBittorrent** – torrent client, <http://localhost:8080>
* **Prowlarr** – search UI across public indexers, sends results to qBittorrent, <http://localhost:9696>
* **FlareSolverr** (for indexers behind Cloudflare) and optional **bitmagnet** (profile `bitmagnet`, own DHT index)

## Requirements

* [uv](https://docs.astral.sh/uv/) (`brew install uv`) – dependencies (boto3) are installed automatically
* [OrbStack](https://orbstack.dev) (`brew install orbstack`, then `open -a OrbStack`) – lightweight
  Docker runtime; Docker Desktop or Colima work too
* `~/.aws/credentials` with an IAM user that has EC2 permissions:

```
[default]
aws_access_key_id = ...
aws_secret_access_key = ...
```

## How to use

A typical download session:

1. **Start the VPN endpoint** (pick any region; the exit IP will be from there):

   ```fish
   ./autovpn -C -r eu-north-1
   ```

2. **Start the stack** – gluetun connects to the endpoint from step 1, the rest starts once the tunnel is healthy:

   ```fish
   docker compose up -d
   ```

3. **Check that traffic leaves via EC2** – this must print the EC2 IP, not your home IP:

   ```fish
   docker compose exec qbittorrent curl -s ifconfig.me
   ```

4. **Search** – open <http://localhost:9696>, *Search*, then the download icon on a result sends it
   to qBittorrent. Or add a `.torrent`/magnet directly at <http://localhost:8080>.
   Finished files land in `/Volumes/T7/qbittorrent/completed`.

5. **Clean up** – EC2 bills per hour, so terminate when done:

   ```fish
   docker compose down
   ./autovpn -T -r eu-north-1 -z all
   ```

Each `-C` creates a fresh endpoint and overwrites `custom/default.ovpn`; after switching
endpoints run `docker compose restart`, then repeat step 3.

Credentials and `*.pem` files are secrets: never commit them (see [Moving to another Mac](#moving-to-another-mac)).

## Setup notes

App settings live in `./config/` (gitignored). On a fresh `config/`:

* **qBittorrent** – login `admin`, temporary password from `docker compose logs qbittorrent | grep password`;
  set your own under *Tools → Options → WebUI*. Recommended (EC2 egress costs ~$0.09/GB, so don't seed much):
  * *Downloads*: default save path `/downloads/completed`, incomplete `/downloads/incomplete`
  * *BitTorrent*: stop seeding at ratio 0.1; *Speed*: upload limit 1 MB/s
  * *WebUI*: *Bypass authentication for clients on localhost* – lets Prowlarr connect without
    a password (it shares gluetun's network); the host and tailnet still need to log in
  * *WebUI*: *Bypass authentication for clients in whitelisted IP subnets* `0.0.0.0/0, ::/0` –
    no login at all (OK because the port is bound to localhost, reachable only via `tailscale serve`)
* **Prowlarr** – *Settings → Download Clients → qBittorrent*, host `localhost`, port `8080`.
  *Indexers → Add*: pick public ones and keep those whose test passes. Many sites
  (e.g. The Pirate Bay) block AWS IPs via Cloudflare; FlareSolverr helps for some
  (*Settings → Indexers → FlareSolverr*,
  host `http://localhost:8191/`, tag it and give the indexer the same tag).

### Access from the tailnet

All UIs are bound to localhost. `tailscale serve` makes them reachable from your other
tailnet devices. The Tailscale daemon on this Mac listens on the tailnet IP, terminates HTTPS
with an automatic Let's Encrypt cert for the MagicDNS name, and proxies to the local port.
Nothing is exposed to the internet (that would be `tailscale funnel`). `--bg` keeps the config
across reboots. Run once:

```fish
tailscale serve --bg --https=8080 http://127.0.0.1:8080   # qBittorrent
tailscale serve --bg --https=9696 http://127.0.0.1:9696   # Prowlarr
tailscale serve status                                    # list mappings
tailscale serve --https=8080 off                          # remove one
```

The URLs are `https://<host>.<tailnet>.ts.net:<port>`. On wien:

* Prowlarr (search): <https://wien.kite-ling.ts.net:9696>
* qBittorrent: <https://wien.kite-ling.ts.net:8080>

This needs MagicDNS and HTTPS certificates enabled in the Tailscale admin console (*DNS* page).

### bitmagnet (optional)

Own search index built by crawling the BitTorrent DHT, no third-party sites involved:

```fish
docker compose --profile bitmagnet up -d   # UI http://localhost:3333
```

In Prowlarr add it as *Generic Torznab*, URL `http://localhost:3333/torznab`.
It needs to run for days to build a useful index and its crawl traffic goes through EC2
(egress costs), so stop it with `docker compose --profile bitmagnet stop bitmagnet postgres`.

## Usage

```fish
./autovpn -C -r us-east-1          # create endpoint (keypair us-east-1_vpnkey.pem auto-created)
docker compose up -d               # stack via VPN -> Prowlarr :9696, qBittorrent :8080
./autovpn -S -r us-east-1          # list running endpoints
./autovpn -T -r us-east-1 -z all   # terminate when done (stop paying)
docker compose down
```

`-C` writes `<region>_aws_vpn.ovpn` and `custom/default.ovpn` (used by gluetun).
Downloads go to `/Volumes/T7/qbittorrent`; startup aborts if T7 is not mounted.
Override with `DOWNLOAD_DIR=/path docker compose up -d`.
OrbStack needs *Removable Volumes* access (System Settings → Privacy & Security → Files & Folders).

Verify the exit IP (gluetun also logs it):

```fish
docker compose logs gluetun | grep "Public IP"
```

## Options

```
-C | -S | -T | -G | -D   create | status | terminate | generate key | delete key
-r REGION                required, any AWS region
-k KEYNAME               keypair (default <region>_vpnkey, expects ./<keyname>.pem)
-i TYPE                  instance type (default t4g.micro; AMI arch is detected)
-a AMI                   custom AMI (default: latest Ubuntu 24.04 from Canonical)
-u USER                  ssh user (default ubuntu)
-p PORT                  OpenVPN UDP port (default 1194)
-d "DNS ..."             DNS pushed to clients (default "1.1.1.1 9.9.9.9")
-m                       allow multiple connections with same config
-z ID|all                instance to terminate
-y                       skip confirmations
```

## Moving to another Mac

Install `uv` and OrbStack (see [Requirements](#requirements)), clone the repo, then copy `~/.aws/credentials` and the `*.pem` files (gitignored), or just let `-C` create new keys
(delete a key whose `.pem` is lost with `./autovpn -D -r <region> -k <region>_vpnkey`).
