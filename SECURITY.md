# Security

## Reporting a problem

Please report vulnerabilities privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Please don't open a public issue for security problems.

## What's protected

**Web server** ([`server/files.ts`](server/files.ts))
- Serves only the `web`, `src` and `games` folders. Path traversal (including encoded `..`, backslashes and null bytes) returns 404.
- Accepts only `GET` and `HEAD`. A malformed address returns 400 instead of crashing the server.
- Sends a strict Content Security Policy (scripts only from this site, no plugins, no framing, no form posts), plus `nosniff`, `no-referrer`, `X-Frame-Options: DENY`, `Cross-Origin-Opener-Policy` and a locked-down `Permissions-Policy`.

**Link-cable relay** ([`server/relay.ts`](server/relay.ts))
- Accepts WebSocket connections only from pages on the same host.
- Validates every message field by field and re-serialises it before passing it on, so nothing unexpected reaches the other player.
- Requires masked, unfragmented frames of at most 256 bytes.
- Limits each connection to 300 messages a second, each address to 10 join attempts a minute, and the server to 200 connections. Idle connections close after 10 minutes.
- Room codes come from a cryptographic random source.

**Pages** ([`web/`](web))
- No `innerHTML`, `eval` or inline scripts. Nerd Mode builds its text with DOM nodes.
- Link messages from the other player are validated, and the lockstep only accepts button presses for frames inside its window, so a hostile peer can't grow memory.
- A saved level must be exactly 17 rows of 128 plain characters before it's spliced into the cartridge source. A damaged save state rolls back instead of corrupting the running game.
- The hosted copy carries the same Content Security Policy as a `<meta>` tag, because GitHub Pages can't send headers.

**Supply chain**
- Zero runtime and zero development dependencies.
- GitHub Actions are pinned to full commit SHAs and kept current by Dependabot. The workflow token is read-only apart from the Pages deployment, and the checkout doesn't keep credentials.
- Secret scanning and push protection are on.

## Trust model

`npm start` is a local server for your own Wi-Fi. Anyone on that network can load the game and join a room if they know its code. It serves only the game's public files and holds no user data. Don't expose it to the internet without HTTPS in front of it. Saves, levels and studio code stay in your browser's local storage and are never uploaded.
