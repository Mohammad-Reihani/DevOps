# Adding Filtering using iptables

Maybe you want to make a safe version for the kids, in that case we should extend the docker image and add some extra tools to do the magic.

## Trojan Kidsafe — Blocklist-enabled Docker setup

This repository contains a small, documented setup to run the `trojangfw/trojan` server inside a custom Docker image that supports blocking destinations listed in a `blocklist.txt` using `ipset` + `iptables`.

---

## What this does

- Builds a custom Docker image based on the official `trojangfw/trojan:latest` image.
- Installs `ipset`, `iptables` and DNS resolving tools (`dig`/`getent`) inside the image.
- Adds an entrypoint script that:

  - Reads `blocklist.txt` mounted into `/config/blocklist.txt`.
  - Resolves hostnames to A/AAAA records (if needed) and stores IP addresses inside `ipset` sets (`blocklist4` and `blocklist6`).
  - Installs `iptables`/`ip6tables` rules to REJECT outbound traffic whose destination matches the ipsets.
  - Periodically refreshes the resolved IPs (default every 300s) in the background.
  - Starts the trojan binary with the configured command.

---

## Files

- `Dockerfile` — extends the official trojan image and installs required tools.
- `start-with-blocklist.sh` — entrypoint that manages ipsets/iptables and runs trojan.
- `docker-compose.yml` — example service configuration showing `cap_add: - NET_ADMIN` and mounting `./blocklist.txt`.
- `blocklist.txt` — sample blocklist (one domain or IP per line; `#` for comments).

---

## Usage (quick)

1. Directory layout (example):

```
your-compose-dir/
├─ docker-compose.yml
├─ blocklist.txt
├─ Dockerfile
└─ start-with-blocklist.sh
```

2. Build and run with Docker Compose:

```bash
# from your-compose-dir
docker compose build trojan-kidsafe
docker compose up -d
```

If you prefer building manually:

```bash
docker build -t trojan-kidsafe-custom ./trojan-custom
docker run --rm -it --cap-add=NET_ADMIN -v $(pwd)/blocklist.txt:/config/blocklist.txt:ro \
  -v /etc/trojan/kidsafe/config.json:/config/config.json:ro \
  -p 110:110 trojan-kidsafe-custom trojan -c /config/config.json
```

> **Important:** `cap_add: - NET_ADMIN` is required so the container can manage ipset/iptables. Do **not** run with `network_mode: host` unless you intentionally want to modify the host network namespace.

---

## `blocklist.txt` format

- One entry per line.
- Lines starting with `#` are ignored.
- Entries can be:

  - IPv4 addresses (e.g. `198.51.100.23`)
  - IPv6 addresses (e.g. `2001:db8::1`)
  - Domain names (e.g. `bad.example.com`) — these will be resolved to A/AAAA records and stored in the ipsets.

Sample:

```
# blocklist.txt
example-bad-site.com
198.51.100.23
2606:4700:4700::1111
```

---

## How it works (internals)

- On container start, two ipset sets are created: `blocklist4` (IPv4) and `blocklist6` (IPv6).
- `iptables -I OUTPUT 1 -m set --match-set blocklist4 dst -j REJECT` is inserted to reject outbound traffic to any IPv4 member of the set. Similar rule is inserted for IPv6 if `ip6tables` is available.
- The script resolves domain names using `dig` (or `getent` fallback), adds the resolved addresses to the appropriate ipset and flushes/re-populates the sets on each refresh.
- The trojan binary is executed as the final `exec` of the entrypoint so it inherits the container's PID 1.

---

## Testing & verification (commands you can run)

Inside the running container (example `docker exec -it trojan-kidsafe`):

```bash
# List ipset contents
ipset list blocklist4
ipset list blocklist6

# Inspect iptables rules
iptables -L OUTPUT -n -v --line-numbers
ip6tables -L OUTPUT -n -v --line-numbers  # if available

# Test DNS resolution
dig +short example-bad-site.com

# Test connectivity (blocked / allowed)
ping -c 2 instagram.com   # expected: Operation not permitted (blocked)
ping -c 2 google.com      # expected: success (not blocked)

# View running container logs
docker logs trojan-kidsafe
```

You already ran the above: ipset shows IPv4/IPv6 members and ping to instagram returned `Operation not permitted` while google succeeded — ✅ that demonstrates blocking is working.

---

## Troubleshooting

- **`dig` not found or resolution fails** — ensure image installation succeeded and `bind-tools` / `dnsutils` are installed during Dockerfile build. Check `docker build` logs.
- **No ipset/ip6tables on the host** — The container contains the tools, but the kernel must support ipset/ip6tables. Most modern kernels do. If rules fail, check `dmesg` on the host and `docker logs` for error messages.
- **iptables rules not effective** — verify the rules are in the container namespace (not host) unless you intentionally use `network_mode: host`.
- **Blocking too broad** — blocking an IP may affect multiple domains that share the same IP (CDNs). Consider carefully whether blocking by domain->IP is sufficient for your needs.

---

## Alternatives and improvements

- Use `inotifywait` to reload immediately on `blocklist.txt` changes (requires `inotify-tools`).
- Perform SNI/TLS-based blocking at the proxy layer (if you can intercept TLS SNI; trojan may not support that directly).
- Run ipset/iptables on the host (or a dedicated gateway container) to block for multiple containers at once.
- Use a small management service (or systemd timer) on the host to keep the host-level ipset up-to-date.

---

## Security notes

- Running containers with `NET_ADMIN` increases privileges; treat the image carefully and run only trusted code.
- Blocking by IP can unintentionally block unrelated services on the same IP (CDN-hosted sites). Use targeted domain-level controls when possible.

---

## License

This README and scripts are provided as-is. You may reuse them in your projects.

---

## Appendix: files (for convenience)

- `Dockerfile`
- `start-with-blocklist.sh`
- `docker-compose.yml` snippet
- `blocklist.txt`

(See repository root for the actual files.)

## NOTE

built the image using:

```bash
docker-compose build trojan-kidsafe
```
