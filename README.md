# autovpn

Spin up an on-demand OpenVPN endpoint on EC2 (~1 min) and run Transmission through it in Docker.

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

2. **Start Transmission** – it connects through the endpoint from step 1:

   ```fish
   docker compose up -d
   ```

3. **Check that traffic leaves via EC2** – this must print the EC2 IP, not your home IP:

   ```fish
   docker compose exec transmission curl -s ifconfig.me
   ```

4. **Download** – open <http://localhost:9091>, add a `.torrent` file or magnet link.
   Finished files land in `~/Movies/transmission1`.

5. **Clean up** – EC2 bills per hour, so terminate when done:

   ```fish
   docker compose down
   ./autovpn -T -r eu-north-1 -z all
   ```

Each `-C` creates a fresh endpoint and overwrites `custom/default.ovpn`; after switching
endpoints run `docker compose restart`, then repeat step 3.

Credentials and `*.pem` files are secrets: never commit them (see [Moving to another Mac](#moving-to-another-mac)).

## Usage

```fish
./autovpn -C -r us-east-1          # create endpoint (keypair us-east-1_vpnkey.pem auto-created)
docker compose up -d               # transmission via VPN -> http://localhost:9091
./autovpn -S -r us-east-1          # list running endpoints
./autovpn -T -r us-east-1 -z all   # terminate when done (stop paying)
docker compose down
```

`-C` writes `<region>_aws_vpn.ovpn` and `custom/default.ovpn` (used by docker compose).
Downloads go to `~/Movies/transmission1`; override with `DOWNLOAD_DIR=/path docker compose up -d`.

Verify the container uses the EC2 IP:

```fish
docker compose exec transmission curl -s ifconfig.me
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
