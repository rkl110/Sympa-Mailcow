#!/bin/bash
systemctl stop postfix@-.service
cd /opt/mailcow-dockerized && docker compose down
#certbot renew --quiet
certbot renew 
cp /etc/letsencrypt/live/DOMAIN/fullchain.pem ./data/assets/ssl/cert.pem
cp /etc/letsencrypt/live/DOMAIN/privkey.pem ./data/assets/ssl/key.pem
docker compose up -d
systemctl start postfix@-.service
