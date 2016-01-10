# auto-letsencrypt-vps

Quick script to automatically get/renew SSL certs for all of my domains that
are currently hosted on a given VPS. 

Assumptions:

* DNS hosted with Cloudflare: query their API to determine what subdomains are
  pointed at a current webhost via A record or CNAME.

* Web domains are stored in /var/www/$DOMAIN, with certificates stored in an
  ssl subdirectory.

* simp_le client is stored at /usr/local/sbin
