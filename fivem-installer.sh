#!/bin/bash
#
# FiveM Server mit TxAdmin und phpMyAdmin Automatisches Installationsscript
# Für Debian 12
#

# Farbdefinitionen
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Root-Rechte prüfen
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Bitte führen Sie das Script als Root aus!${NC}"
  exit 1
fi

# Prüfen, ob es sich um Debian 12 handelt
if [ ! -f /etc/debian_version ] || ! grep -q "12" /etc/debian_version; then
  echo -e "${RED}Dieses Script ist nur für Debian 12 konzipiert.${NC}"
  exit 1
fi

clear
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                           ║${NC}"
echo -e "${BLUE}║${NC}   ${GREEN}FiveM Server mit TxAdmin und phpMyAdmin - Installer${NC}     ${BLUE}║${NC}"
echo -e "${BLUE}║                                                           ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Dieses Script installiert:${NC}"
echo -e "  - FiveM Server mit TxAdmin"
echo -e "  - MySQL/MariaDB"
echo -e "  - phpMyAdmin"
echo -e "  - Nginx als Webserver"
echo -e "  - UFW Firewall"
echo ""
echo -e "${RED}WICHTIG: Dieses Script ist für eine frische Debian 12 Installation gedacht.${NC}"
echo ""

# Benutzer nach Bestätigung fragen
read -p "Möchten Sie fortfahren? (j/n): " choice
if [[ ! "$choice" =~ ^[jJ]$ ]]; then
  echo -e "${RED}Installation abgebrochen.${NC}"
  exit 1
fi

# Benutzerinformationen sammeln
echo ""
echo -e "${YELLOW}Bitte geben Sie die folgenden Informationen ein:${NC}"
read -p "FiveM Server Name: " SERVER_NAME
read -p "FiveM Lizenzschlüssel (von keymaster.fivem.net): " LICENSE_KEY
read -p "MySQL Root Passwort: " MYSQL_ROOT_PASSWORD
read -p "phpMyAdmin Benutzername: " PMA_USERNAME
read -p "phpMyAdmin Passwort: " PMA_PASSWORD

# Bestätigung
echo ""
echo -e "${YELLOW}Zusammenfassung:${NC}"
echo -e "  - Server Name: ${SERVER_NAME}"
echo -e "  - MySQL Root Passwort: ${MYSQL_ROOT_PASSWORD}"
echo -e "  - phpMyAdmin Benutzer: ${PMA_USERNAME}"
echo ""
read -p "Sind diese Informationen korrekt? (j/n): " confirm
if [[ ! "$confirm" =~ ^[jJ]$ ]]; then
  echo -e "${RED}Installation abgebrochen.${NC}"
  exit 1
fi

# System aktualisieren
echo -e "\n${GREEN}[1/7] System wird aktualisiert...${NC}"
apt update && apt upgrade -y

# Benötigte Pakete installieren
echo -e "\n${GREEN}[2/7] Benötigte Pakete werden installiert...${NC}"
apt install -y wget git curl xz-utils screen ufw nginx mariadb-server php php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-zip unzip

# MySQL/MariaDB konfigurieren
echo -e "\n${GREEN}[3/7] MySQL/MariaDB wird konfiguriert...${NC}"
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
mysql -e "CREATE USER '${PMA_USERNAME}'@'localhost' IDENTIFIED BY '${PMA_PASSWORD}';"
mysql -e "GRANT ALL PRIVILEGES ON *.* TO '${PMA_USERNAME}'@'localhost' WITH GRANT OPTION;"
mysql -e "FLUSH PRIVILEGES;"

# phpMyAdmin installieren
echo -e "\n${GREEN}[4/7] phpMyAdmin wird installiert...${NC}"
mkdir -p /var/www/html/phpmyadmin
cd /tmp
wget https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.zip
unzip phpMyAdmin-5.2.1-all-languages.zip
cp -a phpMyAdmin-5.2.1-all-languages/* /var/www/html/phpmyadmin/
rm -rf phpMyAdmin-5.2.1-all-languages.zip phpMyAdmin-5.2.1-all-languages
cp /var/www/html/phpmyadmin/config.sample.inc.php /var/www/html/phpmyadmin/config.inc.php
BLOWFISH_SECRET=$(openssl rand -base64 32)
sed -i "s/\$cfg\['blowfish_secret'\] = ''/\$cfg\['blowfish_secret'\] = '${BLOWFISH_SECRET}'/" /var/www/html/phpmyadmin/config.inc.php
chown -R www-data:www-data /var/www/html/phpmyadmin

# Nginx für phpMyAdmin konfigurieren
cat > /etc/nginx/sites-available/default << EOL
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root /var/www/html;
    index index.php index.html index.htm;
    
    server_name _;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location /phpmyadmin {
        root /var/www/html/;
        index index.php;
        
        location ~ ^/phpmyadmin/(.+\.php)\$ {
            try_files \$uri =404;
            fastcgi_pass unix:/var/run/php/php-fpm.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            include fastcgi_params;
        }
        
        location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))\$ {
            root /var/www/html/;
        }
    }
    
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php-fpm.sock;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOL

systemctl restart nginx

# FiveM mit TxAdmin installieren
echo -e "\n${GREEN}[5/7] FiveM mit TxAdmin wird installiert...${NC}"
mkdir -p /opt/fivem
cd /opt/fivem
wget -q --show-progress https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/6683-9729577be50de537692c3a19e86365a5e0f99a54/fx.tar.xz
tar xf fx.tar.xz
rm fx.tar.xz

# TxAdmin Setup vorbereiten
mkdir -p /opt/fivem/server-data

# Systemd Service für FiveM erstellen
cat > /etc/systemd/system/fivem.service << EOL
[Unit]
Description=FiveM Server with TxAdmin
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/fivem
ExecStart=/opt/fivem/run.sh +set serverProfile default +set txAdminPort 40120
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable fivem.service

# Firewall konfigurieren
echo -e "\n${GREEN}[6/7] Firewall wird konfiguriert...${NC}"
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 30120/tcp
ufw allow 30120/udp
ufw allow 40120/tcp
ufw --force enable

# Abschluss und Zusammenfassung
echo -e "\n${GREEN}[7/7] FiveM Server wird gestartet...${NC}"
systemctl start fivem.service

# IP-Adresse abrufen
SERVER_IP=$(hostname -I | cut -d' ' -f1)

echo -e "\n${GREEN}Installation abgeschlossen!${NC}"
echo -e "\n${YELLOW}Zugriffsdaten:${NC}"
echo -e "  - TxAdmin: http://${SERVER_IP}:40120"
echo -e "  - phpMyAdmin: http://${SERVER_IP}/phpmyadmin"
echo -e "  - MySQL/MariaDB:"
echo -e "    * Benutzername: ${PMA_USERNAME}"
echo -e "    * Passwort: ${PMA_PASSWORD}"
echo -e "    * Root-Passwort: ${MYSQL_ROOT_PASSWORD}"
echo ""
echo -e "${YELLOW}Wichtige Informationen:${NC}"
echo -e "  1. Richten Sie Ihren FiveM-Server über das TxAdmin-Panel ein."
echo -e "  2. Verwenden Sie Ihren FiveM-Lizenzschlüssel: ${LICENSE_KEY}"
echo -e "  3. Für die Serverkonfiguration wird empfohlen, den Server-Namen zu verwenden: ${SERVER_NAME}"
echo -e "  4. Der FiveM-Server läuft als Systemdienst. Verwenden Sie folgende Befehle zur Steuerung:"
echo -e "     - Status prüfen: systemctl status fivem"
echo -e "     - Neustarten: systemctl restart fivem"
echo -e "     - Stoppen: systemctl stop fivem"
echo -e "     - Starten: systemctl start fivem"
echo ""
echo -e "${GREEN}Viel Spaß mit Ihrem neuen FiveM-Server!${NC}"