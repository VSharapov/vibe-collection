# dhcp-client-annotator

Annotate DHCP clients with human-readable names. Track devices coming/going.

Verified on: **ASUS RT-AC66R running ASUSWRT-Merlin 380.70**

## Lease Fetching

Priority order:
1. `GET_LEASES_COMMAND` env var (shell command)
2. `./GET_LEASES_COMMAND` executable file (symlink this)
3. Default: SSH to router

For faster polling, [set up a telnetd service][1] and symlink:
```sh
ln -s get-dnsmasq-via-telnet.sh GET_LEASES_COMMAND
```

[1]: get-dnsmasq-via-telnet.README.md

## devices.json

```json
{
  "annotations": {
    "aabbccddeeff": "Living room TV"
  },
  "uninteresting": ["aabbccddeeff"]
}
```
