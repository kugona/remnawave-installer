# Troubleshooting

Common issues and solutions for the remnawave-installer.

## DNS Configuration

**Problem:** Installation fails or SSL certificates not obtained.

**Solution:**
- Ensure DNS A-records for all domains point to correct IP addresses **before** running the script
- Wait for DNS propagation (can take up to 48 hours, usually 5-15 minutes)
- Verify with: `dig +short your-domain.com`

## Cloudflare Proxy

**Problem:** Selfsteal domain not working with VLESS REALITY.

**Solution:**
- For Selfsteal domain, **disable** Cloudflare proxying (orange cloud)
- DNS record should be "DNS Only" (gray cloud)
- The script will try to detect this, but verify manually

## Docker Hub Rate Limits

**Problem:** `You have reached your pull rate limit` error during installation.

**Solutions:**
1. Authenticate with Docker Hub:
   ```bash
   docker login
   ```
2. Wait 6 hours for limit reset
3. Use a different IP address or VPN

## Port Conflicts

**Problem:** Services fail to start, ports already in use.

**Solution:**
- The script should run on a "clean" server
- Stop conflicting services:
  ```bash
  sudo systemctl stop nginx apache2
  sudo lsof -i :80 -i :443
  ```

## Firewall Issues

**Problem:** Services running but not accessible.

**Solution:**
- Script configures UFW automatically
- If using another firewall, manually open ports:
  - 80/tcp, 443/tcp (for Angie; port 80 is required to issue and renew certificates)
  - Your SSH port
  - 2222/tcp (if needed for node communication)

## All-in-One Panel Access Lost

**Problem:** Panel inaccessible after stopping Xray node.

**Cause:** In All-in-One mode, Angie receives traffic through Xray fallback.

**Solutions:**
1. **Emergency Access** (via script menu): Opens direct access on port 8443
2. **Manual fix**: In `/opt/remnawave/angie/conf.d/sites.conf`, change `listen unix:/dev/shm/angie.sock ssl proxy_protocol` to `listen 443 ssl` after stopping the node, then restart Angie

## Service Management

### Check service status
```bash
cd /opt/remnawave  # or /opt/remnanode
docker compose ps
```

### View logs
```bash
make logs
# or
docker compose logs -f
```

### Restart services
```bash
make restart
```

## Credentials Lost

**Location:** `/opt/remnawave/credentials.txt`

**If deleted:** You can view some values in `.env` files, but passwords may need to be reset via CLI:
```bash
# Access Remnawave CLI
docker exec -it remnawave /bin/sh
```

## Update Issues

**Problem:** Update stuck or failed.

**Solution:**
1. Check Docker daemon is running
2. Verify internet connection
3. Manual update:
   ```bash
   cd /opt/remnawave
   docker compose pull
   docker compose up -d --force-recreate
   ```

## Getting Help

- Check logs first: `make logs`
- Official docs: [https://docs.rw/](https://docs.rw/)
- Telegram group: [@remnawave discussion](https://t.me/+xQs17zMzwCY1NzYy)
- Script issues: [@xxphantom](https://t.me/uphantom)
