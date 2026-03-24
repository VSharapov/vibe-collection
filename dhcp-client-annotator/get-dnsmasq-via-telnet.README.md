# get-dnsmasq-via-telnet.sh

Fetches DHCP leases via telnetd instead of SSH (faster and no sshd-related load spikes).

Verified on: **ASUS RT-AC66R running ASUSWRT-Merlin 380.70**

## Router Setup

Paste into a root shell on the router:

```sh
nvram set jffs2_scripts=1
nvram commit

mkdir -p /jffs/scripts

cat > /jffs/scripts/serve-leases.sh << 'EOF'
#!/bin/sh
cat /var/lib/misc/dnsmasq.leases
exit 0
EOF
chmod +x /jffs/scripts/serve-leases.sh

cat > /jffs/scripts/services-start << 'EOF'
#!/bin/sh
telnetd -p 19999 -l /jffs/scripts/serve-leases.sh -K &
logger -t lease-server "Started lease server on port 19999"
EOF
chmod +x /jffs/scripts/services-start
/jffs/scripts/services-start
```

## Security

Port 19999 is exposed to **anyone on LAN** (no auth). Default iptables rules block WAN access.
