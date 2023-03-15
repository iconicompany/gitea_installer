#!/bin/bash

# -----------------------------------------------------------------------------
# GITEA Installer with Nginx, MariaDB, UFW & Letsencrypt
# Version 0.1
# Written by Maximilian Thoma 2020
# Visit https://lanbugs.de for further informations.
# -----------------------------------------------------------------------------
# gitea_installer.sh is free software;  you can redistribute it and/or
# modify it under the  terms of the  GNU General Public License  as
# published by the Free Software Foundation in version 2.
# gitea_installer.sh is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; with-out even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the  GNU General Public License for more details.
# You should have  received  a copy of the  GNU  General Public
# License along with GNU Make; see the file  COPYING.  If  not,  write
# to the Free Software Foundation, Inc., 51 Franklin St,  Fifth Floor,
# Boston, MA 02110-1301 USA.
#

LETSENCRYPT='false'
UFW='false'

#GETOPTS
while getopts f:e:i:p:r:lu flag
do
    case "${flag}" in
      f) FQDN=${OPTARG};;
      e) EMAIL=${OPTARG};;
      i) IP=${OPTARG};;
      p) PASSWORD=${OPTARG};;
      r) SQLROOT=${OPTARG};;
      l) LETSENCRYPT='true';;
      u) UFW='true';;
    esac
done

if [ -z "$FQDN" ] || [ -z "$EMAIL" ] || [ -z "$IP" ] || [ -z "$PASSWORD" ] || [ -z "$SQLROOT" ]; then
echo "One of the options is missing:"
echo "-f FQDN - Systemname of GITEA system"
echo "-e EMAIL - E-Mail for letsencrypt"
echo "-i IP - IPv4 address of this system"
echo "-p PASSWORD - Used for GITEA DB"
echo "-r SQLROOT - Postgres ROOT password"
echo "-l LETSENCRYPT - Use letsencrypt"
echo "-u UFW - Use UFW"
exit
fi

# Check if curl is installed
if [ ! -x /usr/bin/curl ] ; then
CURL_NOT_EXIST=1
apt install -y curl
else
CURL_NOT_EXIST=0
fi

# Install packages
apt update
apt install -y nginx postgresql postgresql-client git ssl-cert

# Get last version
VER=$(curl --silent "https://api.github.com/repos/go-gitea/gitea/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's|[v,]||g' )                                               

# Create git user
adduser --system --group --disabled-password --shell /bin/bash --home /home/git --gecos 'Git Version Control' git

# Download gitea
if [ -n "$(uname -a | grep i386)" ]; then
    curl -fsSL -o "/tmp/gitea" "https://dl.gitea.io/gitea/$VER/gitea-$VER-linux-386"
fi

if [ -n "$(uname -a | grep x86_64)" ]; then
  curl -fsSL -o "/tmp/gitea" "https://dl.gitea.io/gitea/$VER/gitea-$VER-linux-amd64"
fi

if [ -n "$(uname -a | grep armv6l)" ]; then
  curl -fsSL -o "/tmp/gitea" "https://dl.gitea.io/gitea/$VER/gitea-$VER-linux-arm-6"
fi

if [ -n "$(uname -a | grep armv7l)" ]; then
  curl -fsSL -o "/tmp/gitea" "https://dl.gitea.io/gitea/$VER/gitea-$VER-linux-arm-7"
fi

# Move binary
mv /tmp/gitea /usr/local/bin
chmod +x /usr/local/bin/gitea

# Create folders
mkdir -p /var/lib/gitea/{custom,data,indexers,public,log}
chown git: /var/lib/gitea/{data,indexers,log}
chmod 750 /var/lib/gitea/{data,indexers,log}
mkdir /etc/gitea
chown root:git /etc/gitea
chmod 770 /etc/gitea

# Get systemd file
curl -fsSL -o /etc/systemd/system/gitea.service https://raw.githubusercontent.com/go-gitea/gitea/master/contrib/systemd/gitea.service

# Enable mariadb requirement in systemd gitea.service script
perl -pi -w -e 's/#Requires=postgresql.service/Requires=postgresql.service/g;' /etc/systemd/system/gitea.service

# Reload & Enable gitea daemon
systemctl daemon-reload
systemctl enable --now gitea

# Create db in mariadb
sudo -u postgres psql << EOT
DROP DATABASE IF EXISTS gitea;
DROP USER IF EXISTS gitea;
create database gitea;
CREATE USER gitea WITH PASSWORD '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON DATABASE gitea to gitea;
EOT

# Create nginx config
cat >> /etc/nginx/sites-enabled/$FQDN << XYZ
server {
    listen 80;
    server_name $FQDN;

    return 301 https://$FQDN\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $FQDN;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    client_max_body_size 50m;

    # Proxy headers
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;

    # SSL parameters
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

    # log files
    access_log /var/log/nginx/$FQDN.access.log;
    error_log /var/log/nginx/$FQDN.error.log;

    # Handle / requests
    location / {
       proxy_redirect off;
       proxy_pass http://127.0.0.1:3000;
    }
}
XYZ

# Restart nginx
service nginx restart

#Aquire certificate letsencrypt
if [ $LETSENCRYPT=='true' ] ; then
apt install -y certbot python3-certbot-nginx
certbot --nginx -d $FQDN --non-interactive --agree-tos -m $EMAIL
fi

# Install if ufw true
if [ $UFW=='true' ] ; then

# UFW installed?
if [ ! -x /usr/sbin/ufw ] ; then
apt install -y ufw
fi

# UFW policy
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw logging on
ufw --force enable

fi


# Cleanup packages
if [[ $CURL_NOT_EXIST == 1 ]]; then
apt remove -y curl
fi

# Final message
echo "--------------------------------------------------------------------------------------"
echo " GITEA $VER installed on system $FQDN"
echo "--------------------------------------------------------------------------------------"
echo " Postgres database        : gitea "
echo " Postgres user            : gitea "
echo " Postgres password        : $PASSWORD "
echo "--------------------------------------------------------------------------------------"
echo " System is accessable via https://$FQDN"
echo "--------------------------------------------------------------------------------------"
echo " >>> You must finish the initial setup <<< "
echo "--------------------------------------------------------------------------------------"
echo " Site Title            : Enter your organization name."
echo " Repository Root Path  : Leave the default /home/git/gitea-repositories."
echo " Git LFS Root Path     : Leave the default /var/lib/gitea/data/lfs."
echo " Run As Username       : git"
echo " SSH Server Domain     : Use $FQDN"
echo " SSH Port              : 22, change it if SSH is listening on other Port"
echo " Gitea HTTP Listen Port: 3000"
echo " Gitea Base URL        : Use https://$FQDN/ "
echo " Log Path              : Leave the default /var/lib/gitea/log"
echo "--------------------------------------------------------------------------------------"
if [ $UFW=='true' ] ; then
echo " Following firewall rules applied:"
ufw status numbered
echo "--------------------------------------------------------------------------------------"
fi
