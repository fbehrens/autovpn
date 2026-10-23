# autovpn

Spin up an on-demand OpenVPN endpoint on EC2 (~1 min) and run Transmission through it in Docker.

## Requirements

* [uv](https://docs.astral.sh/uv/) (`brew install uv`) – dependencies (boto3) are installed automatically
* Docker Desktop
* `~/.aws/credentials` with an IAM user that has EC2 permissions:

```
[default]
aws_access_key_id = ...
aws_secret_access_key = ...
```

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

Copy `~/.aws/credentials` and the `*.pem` files (gitignored), or just let `-C` create new keys
(delete a key whose `.pem` is lost with `./autovpn -D -r <region> -k <region>_vpnkey`).
