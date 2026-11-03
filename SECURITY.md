# Security

## Reporting a problem

Please report vulnerabilities privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Please don't open a public issue for security problems.

## What's protected

**Web server** ([`server/files.ts`](server/files.ts))
- Serves only the `web`, `src` and `games` folders. Path traversal (including encoded `..`, backslashes and null bytes) returns 404.
- Accepts only `GET` and `HEAD`. A malformed address returns 400 instead of crashing the server.
- Sends a strict Content Security Policy (scripts only from this site, no plugins, no framing, no form posts), plus `nosniff`, `no-referrer`, `X-Frame-Options: DENY`, `Cross-Origin-Opener-Policy` and a locked-down `Permissions-Policy`.

**Link-cable relay** ([`src/netplay/room.ts`](src/netplay/room.ts), served by [`server/relay.ts`](server/relay.ts) at home and [`cloudflare/worker.ts`](cloudflare/worker.ts) online)
- Accepts WebSocket connections only from pages on the same host.
- Validates every message field by field and re-serialises it before passing it on, so nothing unexpected reaches the other player.
- Requires masked, unfragmented frames of at most 256 bytes.
- Limits each connection to 300 messages a second. A wrong code closes the connection.
- At home, each address gets 10 join attempts a minute, the server allows 200 connections, and idle connections close after 10 minutes.
- Online, a host nobody joins is closed after 10 minutes and every link ends after an hour, so a forgotten tab can't use up the free daily allowance.
- Room codes come from a cryptographic random source.

**Pages** ([`web/`](web))
- No `innerHTML`, `eval` or inline scripts. Nerd Mode builds its text with DOM nodes.
- Link messages from the other player are validated, and the lockstep only accepts button presses for frames inside its window, so a hostile peer can't grow memory.
- A saved level must be exactly 17 rows of 128 plain characters before it's spliced into the cartridge source. A damaged save state rolls back instead of corrupting the running game.

**Supply chain**
- Zero runtime and zero development dependencies.
- GitHub Actions are pinned to full commit SHAs and kept current by Dependabot. The workflow token is read-only, and the checkout doesn't keep credentials.
- Secret scanning and push protection are on.

## Trust model

The server serves only the game's public files and holds no user data. Anyone who can reach it can load the game and join a room if they know its 4-letter code. On your own Wi-Fi that means your network; on the hosted copy it means the internet, behind Cloudflare's HTTPS. Online, guessing codes costs a new connection each time against roughly 330,000 codes, and every attempt counts toward the daily allowance, so the realistic risk is someone burning that allowance, not joining your game.

If you run `npm start` behind a proxy, set `TRUST_PROXY=1`. The relay then rate-limits by the visitor's address as the proxy recorded it (the last `X-Forwarded-For` entry) instead of the proxy's own, and HTTPS responses add `Strict-Transport-Security`. Don't set it when the server is reached directly, or visitors could fake their address.

Saves, levels and studio code stay in your browser's local storage and are never uploaded.
