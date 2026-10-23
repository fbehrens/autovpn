#!/usr/bin/env bash
# Unattended OpenVPN server install for Ubuntu 24.04 (run as root).
# Env: PORT (default 1194), DNS (space separated, default "1.1.1.1 9.9.9.9"), DUPLICATE_CN (0/1)
# Writes the client config to /root/aws_vpn.ovpn
set -euo pipefail

PORT=${PORT:-1194}
DNS=${DNS:-1.1.1.1 9.9.9.9}
DUPLICATE_CN=${DUPLICATE_CN:-0}
CLIENT=aws_vpn
DIR=/etc/openvpn/server

TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)
IFACE=$(ip -4 route show default | awk '{print $5; exit}')

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -yq openvpn easy-rsa iptables-persistent

# PKI
rm -rf /etc/openvpn/easy-rsa
make-cadir /etc/openvpn/easy-rsa
cd /etc/openvpn/easy-rsa
export EASYRSA_BATCH=1 EASYRSA_CERT_EXPIRE=3650
./easyrsa init-pki
./easyrsa build-ca nopass
./easyrsa build-server-full server nopass
./easyrsa build-client-full "$CLIENT" nopass
cp pki/ca.crt pki/issued/server.crt pki/private/server.key "$DIR"/
openvpn --genkey secret "$DIR"/tc.key

{
	echo "port $PORT
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh none
tls-crypt tc.key
topology subnet
server 10.8.0.0 255.255.255.0
push \"redirect-gateway def1 bypass-dhcp\""
	for d in $DNS; do echo "push \"dhcp-option DNS $d\""; done
	echo "keepalive 10 120
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
user nobody
group nogroup
persist-key
persist-tun
verb 3
explicit-exit-notify"
	if [[ $DUPLICATE_CN == 1 ]]; then echo "duplicate-cn"; fi
} > "$DIR"/server.conf

# Routing / NAT
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/30-openvpn-forward.conf
sysctl -q -p /etc/sysctl.d/30-openvpn-forward.conf
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$IFACE" -j MASQUERADE
netfilter-persistent save

systemctl enable --now openvpn-server@server

# Client config
{
	echo "client
dev tun
proto udp
remote $IP $PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
verb 3"
	echo "<ca>"; cat pki/ca.crt; echo "</ca>"
	echo "<cert>"; sed -ne '/BEGIN CERTIFICATE/,$ p' pki/issued/"$CLIENT".crt; echo "</cert>"
	echo "<key>"; cat pki/private/"$CLIENT".key; echo "</key>"
	echo "<tls-crypt>"; sed -ne '/BEGIN OpenVPN Static key/,$ p' "$DIR"/tc.key; echo "</tls-crypt>"
} > /root/"$CLIENT".ovpn
