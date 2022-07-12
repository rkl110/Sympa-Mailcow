# Installing Sympa and Mailcow

> **Warning**
> This far away from perfekt but it helps me to sort my mind

## Introduction

This guide aims to install and configure [mailcow-dockerized](https://github.com/mailcow/mailcow-dockerized) with [sympa](https://www.sympa.org/) and to provide some useful scripts. An essential condition is, to preserve *Mailcow* in their own installations for independent updates.

This guide is based on the work of:

- [dockerized-mailcow-mailman](https://github.com/g4rf/dockerized-mailcow-mailman) by [g4rf](https://github.com/g4rf)
- [Sympa documentation](https://sympa-community.github.io/manual/)
- [systemausfall wiki](https://systemausfall.org/wikis/howto/Sympa%20mit%20Nginx%20und%20Postfix%20einrichten)

After finishing this guide, [mailcow-dockerized](https://github.com/mailcow/mailcow-dockerized) and [sympa](https://www.sympa.org/) will run and *Apache* as a reverse proxy will serve the web frontends.

The operating system used is an *Ubuntu 22.04 LTS* with minimal installation starting with a clean system.

Clone Repository to: /opt/Sympa-Mailcow

```
cd /opt
git clone git@github.com:rkl110/Sympa-Mailcow.git
```

## Disclaimer

I'm not responsible for any data loss, hardware damage or broken keyboards. This guide comes without any warranty. Make backups before starting, 'coze: **No backup no pity!**

## Variables

```
export GIT_SYMPA_MAILCOW=/opt/Sympa-Mailcow
export DOMAIN=example.org
export MAILCOW_DOMAIN=mail.$DOMAIN
export SYMPA_DOMAIN=lists.$DOMAIN
export LIST_ADMIN_MAIL=listmaster@$DOMAIN
export IP=$(curl ifconfig.me)
export DB_PASSWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
```

## Installation

This guide ist based on different steps:

1. Pretasks - system setup
2. DNS setup
3. Setup Hostname and Time
4. Open Ports on Firewall
5. Install *Apache* as a reverse proxy
6. Obtain ssl certificates with *Let's Encrypt*
7. Install *Local Postfix*
9. Install *Docker*
10. Install *Mailcow*
12. Install *MariaDB*
11. Install *Sympa*
13. 🏃 Run
14. Final configuration of *Mailcow* and *Sympa*

### Pretasks: Ubuntu minimal installation

#### install some packages and unminimize system

```
#export  DEBIAN_FRONTEND=noninteractive
apt-get install --yes vim-tiny dialog cron rsync git curl bash-completion wget \
  ufw pwgen command-not-found zip unzip nload unrar lsof iotop net-tools \
  landscape-common rsyslog file htop screen ncdu parted ca-certificates \
  gnupg lsb-release debconf-utils
apt-mark manual netplan.io software-properties-common fdisk \
  gdisk isc-dhcp-client tzdata
apt-get purge --yes cloud-init cloud-guest-utils multipath-tools \
  cryptsetup btrfs-progs cryptsetup-bin lvm2 apport
apt-get autopurge --yes
apt-get update

unminimize

snap remove lxd
snap remove core20
snap remove snapd
```

#### AutoRootLogin on TTY1 and keybased root login

```
cat << EOF > /etc/systemd/system/getty@tty1.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I xterm-256color
Type=idle
EOF

sed -i 's/^#PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config
systemctl restart sshd
```

#### Install some security packages and litte Firewall setup

```
apt-get install --yes fail2ban

ufw allow OpenSSH
ufw logging off
ufw enable

cat << EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 1h
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
EOF

systemctl enable fail2ban.service --now
systemctl restart fail2ban
```

### DNS setup

Most of the configuration ist covered by *Mailcow*s [DNS setup](https://mailcow.github.io/mailcow-dockerized-docs/prerequisite-dns/). After finishing this setup add another subdomain for *Sympa*, e.g. `lists.example.org` that points to the same server:

```
# Name    Type       Value
lists     IN A       1.2.3.4
lists     IN AAAA    dead:beef
```

### Setup Hostname and Time

```
timedatectl set-timezone Europe/Berlin
#edit /etc/hostname
#edit /etc/hosts
```

### install, setup Postfix

- Install Postfix with 'No configuration'
- setup main.cf and master.cf to listen on custom Docker port 172.22.1.1:2525

```
cat << EOF | debconf-set-selections
postfix postfix/main_mailer_type        select  No configuration
postfix postfix/mailname        string  $MAILCOW_DOMAIN
EOF
apt-get install -y postfix mailutils
cat << EOF > /etc/mailname
local.$MAILCOW_DOMAIN
EOF

# Copy new configuration edit Settings
cp $GIT_SYMPA_MAILCOW/etc/postifx/*.cf /etc/postfix/
# Exit /etc/postfix/main.cf
# Edit /etc/postfix/master.cf

sed -ri "s/MAILCOW_DOMAIN/$MAILCOW_DOMAIN/" /etc/postfix/main.cf
sed -ri "s/SYMPA_DOMAIN/$SYMPA_DOMAIN/" /etc/postfix/main.cf

# Update Systemd Service

cp $GIT_SYMPA_MAILCOW/etc/systemd/postfix@.service /etc/systemd/system/postfix@.service
systemctl daemon-reload
systemctl enable postfix --now
systemctl restart postfix
```

### Add Firwall exeption for mailcow and docker relay/transport

```
# Firewall local MTA
ufw allow from 172.22.0.0/16 to any port 2525
# Firewall Mailcow
ufw allow proto tcp to any port 25,465,587,143,993,110,995,4190,80,443
```

### Install *Apache* as a reverse proxy

Install *Apache*, e.g. with this guide from *Digital Ocean*: [How To Install the Apache Web Server on Ubuntu 20.04](https://www.digitalocean.com/community/tutorials/how-to-install-the-apache-web-server-on-ubuntu-20-04).

Activate certain *Apache* modules (as *root* or *sudo*):

```
apt-get install --yes apache2
a2enmod rewrite proxy proxy_http headers ssl wsgi proxy_uwsgi http2 proxy_fcgi
```

Maybe you have to install further packages to get these modules. This [PPA](https://launchpad.net/~ondrej/+archive/ubuntu/apache2) by *Ondřej Surý* may help you.

#### Obtain ssl certificates with *Let's Encrypt*

Check if your DNS config is available over the internet and points to the right IP addresses, e.g. with [MXToolBox](https://mxtoolbox.com):

- <https://mxtoolbox.com/SuperTool.aspx?action=a%3aMAILCOW_DOMAIN>
- <https://mxtoolbox.com/SuperTool.aspx?action=aaaa%3aMAILCOW_DOMAIN>
- <https://mxtoolbox.com/SuperTool.aspx?action=a%3aSYMPA_DOMAIN>
- <https://mxtoolbox.com/SuperTool.aspx?action=aaaa%3aSYMPA_DOMAIN>

Install [certbot](https://certbot.eff.org/) (as *root* or *sudo*):

```
apt-get install --yes certbot python3-certbot-apache
```

Get the desired certificates (as *root* or *sudo*):

```
certbot certonly -d $DOMAIN -d $MAILCOW_DOMAIN -d $SYMPA_DOMAIN -d mta-sts.$DOMAIN --apache --register-unsafely-without-email --agree-tos
```

#### vhost configuration

Copy the [etc/apache2/mailcow.conf](apache2/mailcow.conf) and [etc/apache2/sympa.conf](apache2/sympa.conf) to the *Apache* conf folder `sites-available` (e.g. under `/etc/apache2/sites-available`).

Change in `mailcow.conf`:

- `MAILCOW_DOMAIN` to your **MAILCOW_DOMAIN** (e.g. `mail.example.org`)
- `DOMAIN` to your **DOMAIN** (e.g. `example.org`)

Change in `sympa.conf`:

- `SYMPA_DOMAIN` to your *Sympa* domain (e.g. `lists.example.org`)
- `DOMAIN` to your **DOMAIN** (e.g. `example.org`)

```
cp $GIT_SYMPA_MAILCOW/etc/apache2/*.conf /etc/apache2/sites-available/
sed -ri "s/MAILCOW_DOMAIN/$MAILCOW_DOMAIN/" /etc/apache2/sites-available/mailcow.conf
sed -ri "s/DOMAIN/$DOMAIN/" /etc/apache2/sites-available/mailcow.conf
sed -ri "s/SYMPA_DOMAIN/$SYMPA_DOMAIN/" /etc/apache2/sites-available/sympa.conf
sed -ri "s/DOMAIN/$DOMAIN/" /etc/apache2/sites-available/sympa.conf

# enable vhost
a2ensite mailcow.conf
a2ensite sympa.conf
a2dissite 000-default.conf
```

### Install Docker

```
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install --yes docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
```

#### Setup docker-compose

```
curl -L https://github.com/docker/compose/releases/download/v$(curl -Ls https://www.servercow.de/docker-compose/latest.php)/docker-compose-$(uname -s)-$(uname -m) > /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
```

### Install *Mailcow*

#### install Mailcow

Follow the [Mailcow installation](https://mailcow.github.io/mailcow-dockerized-docs/i_u_m_install/). **Omit step 5 and do not pull and up with `docker-compose`!**

```
umask # 0022 # <- Verify it is 0022
cd /opt
git clone https://github.com/mailcow/mailcow-dockerized
cd mailcow-dockerized
./generate_config.sh
```

#### configure Mailcow

This is also **Step 4** in the official *Mailcow installation* (`nano mailcow.conf`). So change to your needs and alter the following variables:

```
HTTP_PORT=8080             #
HTTP_BIND=127.0.0.1        # 
HTTPS_PORT=8443            #
HTTPS_BIND=127.0.0.1       # 

SKIP_LETS_ENCRYPT=y        # reverse proxy will do the ssl termination

SNAT_TO_SOURCE=1.2.3.4     # change this to your ipv4
SNAT6_TO_SOURCE=dead:beef  # change this to your global ipv6
```

```
sed -ri 's/HTTP_PORT=.*$/HTTP_PORT=8080/' /opt/mailcow-dockerized/mailcow.conf
sed -ri 's/HTTP_BIND=.*$/HTTP_BIND=127.0.0.1/' /opt/mailcow-dockerized/mailcow.conf
sed -ri 's/HTTPS_PORT=.*$/HTTPS_PORT=8443/' /opt/mailcow-dockerized/mailcow.conf
sed -ri 's/HTTPS_BIND=.*$/HTTPS_BIND=127.0.0.1/' /opt/mailcow-dockerized/mailcow.conf
sed -ri 's/SKIP_LETS_ENCRYPT=.*$/SKIP_LETS_ENCRYPT=y/' /opt/mailcow-dockerized/mailcow.conf
sed -ri "s/SNAT_TO_SOURCE=.*\$/SNAT_TO_SOURCE=$IP/" /opt/mailcow-dockerized/mailcow.conf
```

#### ssl certificates Skript

As we proxying *Mailcow*, we need to copy the ssl certificates into the *Mailcow* file structure. This task will do the script [scripts/renew-ssl.sh](scripts/renew-ssl.sh) for us:

- copy the file to `/opt/mailcow-dockerized`
- change **MAILCOW_DOMAIN** to your *Mailcow* hostname
- make it executable (`chmod a+x renew-ssl.sh`)

You have to create a *cronjob*, so that new certificates will be copied. Execute as *root* or *sudo*:

```
crontab -e
```

To run the script every day at 5am, add:

```
0   5  *   *   *     /opt/mailcow-dockerized/renew-ssl.sh
```


```
cp $GIT_SYMPA_MAILCOW/scripts/renew-ssl.sh /opt/mailcow-dockerized/renew-ssl.sh
chmod +x /opt/mailcow-dockerized/renew-ssl.sh
sed -ri "s/DOMAIN/$DOMAIN/" /opt/mailcow-dockerized/renew-ssl.sh
cat << EOF >> /var/spool/cron/crontabs/root
0   5  *   *   *     /opt/mailcow-dockerized/renew-ssl.sh
EOF
```

### mysql installation and create Sympa user

```
apt-get install --yes mariadb-server
mysql_secure_installation
# fillout whatever you like

mysql << EOF
CREATE USER 'sympa'@'localhost' IDENTIFIED BY '$DB_PASSWD';
CREATE DATABASE IF NOT EXISTS sympa CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
GRANT ALL PRIVILEGES ON sympa.* TO 'sympa'@'localhost';
FLUSH PRIVILEGES;
EOF
```

### preconfiguration Sympa

- copy etc/sympa/sympa.conf to /etc/sympa/sympa/sympa.conf
- copy etc/sympa/aliases.sympa.postfix to /etc/sympa/aliases.sympa.postfix
- create Files and set permissions

```
mkdir -p /etc/mail/sympa
touch /etc/mail/sympa/aliases
postalias hash:/etc/mail/sympa/aliases
chown -R 115:122 /etc/mail/sympa

mkdir -p /etc/sympa/sympa
cp $GIT_SYMPA_MAILCOW/etc/sympa/aliases.sympa.postfix /etc/sympa/aliases.sympa.postfix
cp $GIT_SYMPA_MAILCOW/etc/sympa/sympa.conf /etc/sympa/sympa/sympa.conf
sed -ri "s/SYMPA_DOMAIN/$SYMPA_DOMAIN/" /etc/sympa/aliases.sympa.postfix
sed -ri "s/SYMPA_DOMAIN/$SYMPA_DOMAIN/" /etc/sympa/sympa/sympa.conf
sed -ri "s/DOMAIN/$DOMAIN/" /etc/sympa/sympa/sympa.conf
sed -ri "s/DB_PASSWD/$DB_PASSWD/" /etc/sympa/sympa/sympa.conf
postalias hash:/etc/sympa/aliases.sympa.postfix
chown -R 115:122 /etc/sympa
```

#### DBConfig pass sympa Variables

```
cat << EOF | sudo debconf-set-selections
sympa   sympa/use_soap  boolean false
sympa   sympa/internal/skip-preseed     boolean false
sympa   sympa/database-type     select  mysql
sympa   sympa/language  select  en_US
sympa   sympa/sympa_newaliases-wrapper-setuid-root      boolean false
sympa   wwsympa/remove_spool    boolean true
sympa   sympa/upgrade-backup    boolean true
sympa   wwsympa/webserver_type  select  Apache 2
sympa   sympa/mysql/method      select  Unix socket
sympa   sympa/dbconfig-upgrade  boolean true
sympa   sympa/dbconfig-install  boolean false
EOF
```

#### install sympa

```
apt-get install --no-install-recommends --assume-yes sympa libapache2-mod-fcgid apache2-suexec-pristine
```

#### Fix sympa logging, and docker syslog spam

```
touch /var/log/sympa.log
chown syslog:adm /var/log/sympa.log
sed -ri 's/create 640 sympa sympa/create 640 syslog adm/' /etc/logrotate.d/sympa
systemctl restart logrotate.service
```

```
cat << EOF > sudo /etc/rsyslog.d/01-blocklist.conf
if $msg contains "run-docker-runtime" and $msg contains ".mount: Succeeded." then {
    stop
}
if $msg contains "run-docker-runtime" and $msg contains ".mount: Deactivated successfully." then {
    stop
}
EOF
systemctl restart rsyslog
```


#### [Setup Sympa Database strutkure](https://sympa-community.github.io/manual/install/setup-database-mysql.html)

```
# Create table structure:
/usr/lib/sympa/bin/sympa.pl --health_check
```

#### generate new aliases

```
/usr/lib/sympa/bin/sympa_newaliases.pl
```

### 🏃 Run

Run (as *root* or *sudo*)

```
systemctl restart apache2
systemctl restart postfix
systemctl restart wwsympa.service sympa.service

cd /opt/mailcow-dockerized/
docker-compose pull
./renew-ssl.sh
```

### Cleanup Variables

```
unset GIT_SYMPA_MAILCOW
unset DOMAIN
unset MAILCOW_DOMAIN
unset SYMPA_DOMAIN
unset LIST_ADMIN_MAIL
unset IP
unset DB_PASSWD
```

**Wait a few minutes!** The containers have to create there databases and config files. This can last up to 1 minute and more.

### Setup Mailcow to talk to Sympa/Postfix on Docker Host

```
Configuration & Details -> Configuration -> Forwarding Hosts  
Add DockerHost IP with inactive Spamfilter  
```

```
Configuration & Details -> Routing -> Transport Maps -> Add transport  
Destination: SYMPA_DOMAIN  
Next Hop: 172.22.1.1:2525  
Active ✅
```

```
Mail Setup -> Domains -> Add domain  
Domain: SYMPA_DOMAIN  
Description: SYMPA_DOMAIN  
Global Adress List []  
Active ✅  
Relay options:  
Relay this domain ✅    
Relay all recipiants. ✅    
Relay non-existing mailboxes only. Existing mailboxes will be delivered locally. ✅
```

## Remarks

## Update

**Mailcow** has it's own update script in `/opt/mailcow-dockerized/update.sh', [see the docs](https://mailcow.github.io/mailcow-dockerized-docs/i_u_m_update/).

## Backup

**Mailcow** has an own backup script. [Read the docs](https://mailcow.github.io/mailcow-dockerized-docs/b_n_r_backup/) for further informations.

## ToDo

### Sympa/Mail/Database in Docker

### install script

Write a script like in [mailman-mailcow-integration/mailman-install.sh](https://gitbucket.pgollor.de/docker/mailman-mailcow-integration/blob/master/mailman-install.sh) as many of the steps are automatable.

1. Ask for all the configuration variables
2. Do a (semi-)automatic installation.
3. Have fun!
