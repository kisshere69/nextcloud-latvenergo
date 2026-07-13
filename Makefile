.PHONY: certs-staging certs

# Issue/renew a Let's Encrypt STAGING certificate
certs-staging:
	bash certbot/renew.sh staging

# Issue/renew the real Let's Encrypt PROD certificate
certs:
	bash certbot/renew.sh prod
