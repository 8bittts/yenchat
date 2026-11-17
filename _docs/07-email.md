# Email

Owns the `support@yen.chat` mailbox and the domain's mail authentication.
The desktop app and the website send no email.

## Support Mailbox

- Cloudflare is authoritative DNS for `yen.chat` (`ssl` `strict`, `always_use_https` `on`, `min_tls_version` `1.2`, `email_obfuscation` `off`, `DNSSEC` `disabled`) and runs receive-only Email Routing: apex MX `route1/2/3.mx.cloudflare.net`, subaddressing on, zero custom rules, and the zone catch-all forwarding `support@yen.chat` and any other local part to the operator's Gmail. `yen.chat`, `www.yen.chat` (`df66c444acef2c64.vercel-dns-016.com`), and `files.yen.chat` stay DNS-only to Vercel (no Cloudflare Worker sits in front of `files.yen.chat`). There is no mailbox and no Cloudflare SMTP.
- Resend receiving is also enabled on `yen.chat`, but because the public MX points at Cloudflare, no mail ever reaches Resend inbound for this domain; leave it unused or disable it in Resend, and never build an inbound handler that assumes it.
- Replies go out through Gmail "Send mail as" over Resend SMTP: `smtp.resend.com`, port `587`, user `resend`, a Resend API key as password, TLS. A typo'd `smtp.<domain>` host is the usual failure.
- This works only while `yen.chat` is a verified Resend domain; its DKIM, SPF, return-path (`send.yen.chat`), and `mail.yen.chat -> send.forge.rmta.net` CNAME records stay DNS-only in Cloudflare.
- `deathnote.ai` and `zoe.date` use the same setup, documented in their own repos; the cross-repo BIMI rollout state — which domains carry a live record and which still wait on DMARC enforcement — is owned by the fleet reference [`8leeai/_global/cloudflare.md`](https://github.com/8bittts/8leeai/blob/main/_global/cloudflare.md), section "BIMI", and this document owns only `yen.chat`'s record.

## BIMI

- Logo: `public/yen-bimi.svg`, SVG Tiny Portable/Secure (`baseProfile="tiny-ps"`, a `<title>`, filled paths only), the mark on `#0D1811`, inset 19% per side for the circular crop.
- Record: `default._bimi.yen.chat` TXT `v=BIMI1; l=https://yen.chat/yen-bimi.svg;`.
- [CRITICAL] `_dmarc.yen.chat` stays at `p=quarantine; pct=100` with aggregate reports. Below enforcement no client draws the logo, and nothing reports the failure.
- Gmail and Apple Mail also need a VMC or CMC; Fastmail and Zoho render from the record alone. Validate changes at bimigroup.org.
