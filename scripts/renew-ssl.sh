#!/bin/bash
cd /opt/mailcow-dockerized && docker-compose down
certbot renew --pre-hook "systemctl stop apache2" --post-hook "systemctl start apache2" --renew-hook "systemctl reload apache2" --quiet
cp /etc/letsencrypt/live/DOMAIN/fullchain.pem ./data/assets/ssl/cert.pem
cp /etc/letsencrypt/live/DOMAIN/privkey.pem ./data/assets/ssl/key.pem
docker-compose up -d
