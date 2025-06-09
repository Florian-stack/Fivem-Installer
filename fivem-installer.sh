#!/bin/bash
#
# FiveM Server mit TxAdmin und phpMyAdmin Automatisches Installations- und Update-Script
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

# Funktion zum Generieren sicherer Passwörter
generate_password() {
  openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12
}

# Sofortige PIN-Erfassung beim FiveM-Start
start_fivem_and_capture_pin() {
    local pin=""
    local pin_found=false
    
    echo -e "${GREEN}FiveM Server wird gestartet und PIN wird erfasst...${NC}"
    
    # Erstelle temporäre Datei für PIN-Erfassung
    local temp_log="/tmp/fivem_startup_$(date +%s).log"
    
    # Starte FiveM im Hintergrund und leite Output in temporäre Datei
    cd /opt/fivem
    nohup ./run.sh +set serverProfile default +set txAdminPort 40120 > "$temp_log" 2>&1 &
    local fivem_pid=$!
    
    echo -e "${YELLOW}Überwache Startup-Output für PIN...${NC}"
    
    # Überwache die Log-Datei in Echtzeit
    tail -f "$temp_log" &
    local tail_pid=$!
    
    # Warte auf PIN in der Log-Datei (max 30 Sekunden)
    local counter=0
    while [ $counter -lt 30 ] && [ $pin_found = false ]; do
        if [ -f "$temp_log" ]; then
            pin=$(grep -o "PIN: [0-9]\{4\}" "$temp_log" | tail -1 | cut -d' ' -f2)
            if [ -n "$pin" ]; then
                pin_found=true
                echo -e "\n${GREEN}=== PIN GEFUNDEN: $pin ===${NC}"
                break
            fi
        fi
        sleep 1
        ((counter++))
        echo -n "."
    done
    
    # Stoppe tail-Prozess
    kill $tail_pid 2>/dev/null
    
    if [ $pin_found = true ]; then
        # Stoppe den manuell gestarteten Prozess
        kill $fivem_pid 2>/dev/null
        sleep 2
        
        # Starte jetzt den systemd-Service normal
        systemctl start fivem.service
        
        # Gib PIN zurück
        echo "$pin"
        
        # Räume temporäre Datei auf
        rm -f "$temp_log"
        return 0
    else
        echo -e "\n${RED}PIN nicht innerhalb von 30 Sekunden gefunden!${NC}"
        # Räume auf
        kill $fivem_pid 2>/dev/null
        rm -f "$temp_log"
        return 1
    fi
}

# Alternative Methode: PIN direkt aus der Service-Ausgabe abfangen
start_fivem_with_direct_capture() {
    echo -e "${GREEN}FiveM Server wird gestartet...${NC}"
    
    # Starte Service und erfasse Output
    systemctl start fivem.service
    
    # Erfasse Service-Output sofort
    echo -e "${YELLOW}Erfasse Service-Output...${NC}"
    
    # Warte kurz und erfasse dann die Logs
    sleep 3
    
    # Hole die neuesten Logs vom Service
    local pin=$(journalctl -u fivem.service --since "30 seconds ago" --no-pager | grep -o "PIN: [0-9]\{4\}" | tail -1 | cut -d' ' -f2)
    
    if [ -n "$pin" ]; then
        echo -e "${GREEN}PIN erfolgreich erfasst: $pin${NC}"
        echo "$pin"
        return 0
    else
        # Fallback: Live-Monitoring für 15 Sekunden
        echo -e "${YELLOW}Fallback: Live-Monitoring für 15 Sekunden...${NC}"
        
        timeout 15 journalctl -u fivem.service -f --no-pager | while read -r line; do
            if echo "$line" | grep -q "PIN:"; then
                local found_pin=$(echo "$line" | grep -o "PIN: [0-9]\{4\}" | cut -d' ' -f2)
                if [ -n "$found_pin" ]; then
                    echo "$found_pin" > /tmp/txadmin_pin.txt
                    echo -e "\n${GREEN}PIN gefunden: $found_pin${NC}"
                    break
                fi
            fi
        done
        
        # Lese PIN aus temporärer Datei
        if [ -f "/tmp/txadmin_pin.txt" ]; then
            pin=$(cat /tmp/txadmin_pin.txt)
            rm -f /tmp/txadmin_pin.txt
            echo "$pin"
            return 0
        fi
        
        return 1
    fi
}

# Hauptfunktion für PIN-Erfassung
capture_txadmin_pin() {
    # Prüfe, ob TxAdmin bereits konfiguriert ist
    if [ -f "/opt/fivem/txData/default/config.json" ]; then
        echo -e "${GREEN}TxAdmin ist bereits konfiguriert.${NC}"
        return 2
    fi
    
    echo -e "${BLUE}Starte PIN-Erfassung...${NC}"
    
    # Versuche erste Methode
    local pin=$(start_fivem_with_direct_capture)
    
    if [ -n "$pin" ]; then
        echo "$pin"
        return 0
    fi
    
    echo -e "${YELLOW}Erste Methode fehlgeschlagen, versuche alternative Methode...${NC}"
    
    # Stoppe Service für sauberen Neustart
    systemctl stop fivem.service 2>/dev/null
    sleep 2
    
    # Versuche zweite Methode
    pin=$(start_fivem_and_capture_pin)
    
    if [ -n "$pin" ]; then
        echo "$pin"
        return 0
    fi
    
    return 1
}

# Sofortige PIN-Anzeige-Funktion (für manuelle Verwendung)
show_pin_immediately() {
    echo -e "${BLUE}=== SOFORTIGE PIN-ERFASSUNG ===${NC}"
    echo -e "${YELLOW}Stoppe FiveM-Service...${NC}"
    systemctl stop fivem.service
    
    echo -e "${YELLOW}Starte FiveM manuell für PIN-Erfassung...${NC}"
    cd /opt/fivem
    
    # Starte FiveM und zeige Output direkt an
    timeout 30 ./run.sh +set serverProfile default +set txAdminPort 40120 | tee /tmp/fivem_direct.log &
    
    # Überwache Output in Echtzeit
    tail -f /tmp/fivem_direct.log | while read -r line; do
        echo "$line"
        if echo "$line" | grep -q "PIN:"; then
            PIN=$(echo "$line" | grep -o "PIN: [0-9]\{4\}" | cut -d' ' -f2)
            echo -e "\n${GREEN}=== IHR PIN: $PIN ===${NC}\n"
            echo "PIN: $PIN" > /root/txadmin_pin.txt
            killall run.sh 2>/dev/null
            break
        fi
    done
    
    # Starte Service wieder normal
    systemctl start fivem.service
    rm -f /tmp/fivem_direct.log
}

clear
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                           ║${NC}"
echo -e "${BLUE}║${NC}   ${GREEN}FiveM Server mit TxAdmin und phpMyAdmin - Tool${NC}         ${BLUE}║${NC}"
echo -e "${BLUE}║                                                           ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Dieses Script kann:${NC}"
echo -e "  1) Einen neuen FiveM Server mit TxAdmin installieren"
echo -e "  2) Einen bestehenden FiveM Server aktualisieren"
echo ""

# Auswahl der Aktion
read -p "Bitte wählen Sie eine Option (1 oder 2): " action_choice
if [[ ! "$action_choice" =~ ^[1-2]$ ]]; then
  echo -e "${RED}Ungültige Auswahl. Das Script wird beendet.${NC}"
  exit 1
fi

# Passwörter generieren
MYSQL_ROOT_PASSWORD=$(generate_password)
PMA_PASSWORD=$(generate_password)
PMA_USERNAME="root"

# Installation
if [ "$action_choice" -eq "1" ]; then
  echo -e "\n${GREEN}[1/6] System wird aktualisiert...${NC}"
  apt update && apt upgrade -y

  echo -e "\n${GREEN}[2/6] Benötigte Pakete werden installiert...${NC}"
  apt install -y wget git curl xz-utils screen ufw nginx mariadb-server php php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-zip unzip

  echo -e "\n${GREEN}[3/6] MySQL/MariaDB wird konfiguriert...${NC}"
  mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
  mysql -e "FLUSH PRIVILEGES;"

  echo -e "\n${GREEN}[4/6] phpMyAdmin wird installiert...${NC}"
  mkdir -p /var/www/html/phpmyadmin
  cd /tmp
  # Neueste Version von phpMyAdmin herunterladen
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
fi

# FiveM mit TxAdmin installieren oder aktualisieren
if [ "$action_choice" -eq "1" ]; then
  echo -e "\n${GREEN}[5/6] FiveM mit TxAdmin wird installiert...${NC}"
  mkdir -p /opt/fivem
  cd /opt/fivem
else
  echo -e "\n${GREEN}[1/3] FiveM mit TxAdmin wird aktualisiert...${NC}"
  # Stoppe den FiveM-Service, falls er läuft
  if systemctl is-active --quiet fivem.service; then
    systemctl stop fivem.service
    echo -e "${YELLOW}FiveM-Service wurde gestoppt für das Update.${NC}"
  fi
  
  # Sichere die aktuellen Daten
  if [ -d "/opt/fivem" ]; then
    echo -e "${YELLOW}Sichere wichtige Daten vor dem Update...${NC}"
    # Sichere nur die wichtigen Daten, nicht die gesamte Installation
    if [ -d "/opt/fivem/server-data" ]; then
      mkdir -p /opt/fivem_backup
      cp -r /opt/fivem/server-data /opt/fivem_backup/
      echo -e "${GREEN}Server-Daten wurden gesichert nach /opt/fivem_backup/server-data${NC}"
    fi
    
    # Sichere TxAdmin-Daten
    if [ -d "/opt/fivem/txData" ]; then
      mkdir -p /opt/fivem_backup
      cp -r /opt/fivem/txData /opt/fivem_backup/
      echo -e "${GREEN}TxAdmin-Daten wurden gesichert nach /opt/fivem_backup/txData${NC}"
    fi
  else
    mkdir -p /opt/fivem
  fi
  
  cd /opt/fivem
  # Entferne alte FiveM-Dateien, aber behalte server-data und txData
  find . -maxdepth 1 -not -name "server-data" -not -name "txData" -not -name "." -not -name ".." -exec rm -rf {} \;
  echo -e "${GREEN}Alte FiveM-Dateien wurden entfernt.${NC}"
fi

# Aktuelle FiveM-Version herunterladen
echo -e "${YELLOW}FiveM wird heruntergeladen...${NC}"
# Feste URL für eine bekannte stabile Version
FIVEM_DOWNLOAD_URL="https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/6683-9729577be50de537692c3a19e86365a5e0f99a54/fx.tar.xz"
echo -e "${GREEN}Verwende stabile FiveM-Version...${NC}"
wget -q --show-progress "${FIVEM_DOWNLOAD_URL}" -O fx.tar.xz

# Überprüfen, ob der Download erfolgreich war
if [ $? -ne 0 ] || [ ! -s fx.tar.xz ]; then
  echo -e "${RED}Fehler beim Herunterladen der FiveM-Version.${NC}"
  echo -e "${RED}Bitte überprüfen Sie Ihre Internetverbindung oder versuchen Sie es später erneut.${NC}"
  exit 1
fi

echo -e "${GREEN}Entpacke FiveM...${NC}"
tar xf fx.tar.xz
if [ $? -ne 0 ]; then
  echo -e "${RED}Fehler beim Entpacken der FiveM-Version. Die heruntergeladene Datei könnte beschädigt sein.${NC}"
  exit 1
fi

rm fx.tar.xz

# TxAdmin Setup vorbereiten
mkdir -p /opt/fivem/server-data

# Nur bei Neuinstallation
if [ "$action_choice" -eq "1" ]; then
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
  echo -e "\n${GREEN}[6/6] Firewall wird konfiguriert...${NC}"
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 30120/tcp
  ufw allow 30120/udp
  ufw allow 40120/tcp
  ufw --force enable
else
  echo -e "\n${GREEN}[2/3] Konfiguration wird überprüft...${NC}"
  # Stelle sicher, dass der Service korrekt konfiguriert ist
  if [ ! -f "/etc/systemd/system/fivem.service" ]; then
    echo -e "${YELLOW}FiveM-Service wird neu konfiguriert...${NC}"
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
  fi
  
  # Stelle gesicherte TxAdmin-Daten wieder her
  if [ -d "/opt/fivem_backup/txData" ] && [ ! -d "/opt/fivem/txData" ]; then
    echo -e "${YELLOW}Stelle TxAdmin-Daten wieder her...${NC}"
    cp -r /opt/fivem_backup/txData /opt/fivem/
    echo -e "${GREEN}TxAdmin-Daten wurden wiederhergestellt.${NC}"
  fi
  
  echo -e "\n${GREEN}[3/3] Update abgeschlossen...${NC}"
fi

# IP-Adresse abrufen
SERVER_IP=$(hostname -I | cut -d' ' -f1)

# PIN-Erfassung
echo -e "\n${GREEN}Starte TxAdmin und erfasse PIN...${NC}"

# Erfasse PIN
TXADMIN_PIN_RESULT=$(capture_txadmin_pin)
PIN_STATUS=$?

case $PIN_STATUS in
    0)
        TXADMIN_PIN="$TXADMIN_PIN_RESULT"
        TXADMIN_CONFIGURED=false
        echo -e "${GREEN}PIN erfolgreich erfasst: $TXADMIN_PIN${NC}"
        ;;
    2)
        TXADMIN_CONFIGURED=true
        TXADMIN_PIN=""
        ;;
    *)
        TXADMIN_CONFIGURED=false
        TXADMIN_PIN=""
        echo -e "${RED}PIN konnte nicht erfasst werden!${NC}"
        echo -e "${YELLOW}Bitte starten Sie den Server manuell und suchen Sie nach dem PIN:${NC}"
        echo -e "${BLUE}journalctl -u fivem.service -f | grep PIN${NC}"
        ;;
esac

# Stelle sicher, dass der Service läuft
if ! systemctl is-active --quiet fivem.service; then
    echo -e "${YELLOW}Starte FiveM-Service...${NC}"
    systemctl start fivem.service
fi

# Zusammenfassung anzeigen
echo -e "\n${GREEN}Vorgang abgeschlossen!${NC}"
echo -e "\n${YELLOW}Zugriffsdaten:${NC}"

if [ "$action_choice" -eq "1" ]; then
  echo -e "  - TxAdmin: http://${SERVER_IP}:40120"
  if [ "$TXADMIN_CONFIGURED" = true ]; then
    echo -e "  - TxAdmin ist bereits konfiguriert. Verwenden Sie Ihre bestehenden Anmeldedaten."
  elif [ -n "$TXADMIN_PIN" ]; then
    echo -e "  - TxAdmin PIN: ${TXADMIN_PIN}"
  else
    echo -e "  - TxAdmin PIN: ${RED}Konnte nicht automatisch ermittelt werden.${NC}"
    echo -e "    Für sofortige PIN-Erfassung führen Sie aus:"
    echo -e "    ${YELLOW}# Stoppe den Service und erfasse PIN sofort:${NC}"
    echo -e "    ${BLUE}systemctl stop fivem.service && cd /opt/fivem && ./run.sh +set serverProfile default +set txAdminPort 40120${NC}"
  fi
  echo -e "  - phpMyAdmin: http://${SERVER_IP}/phpmyadmin"
  echo -e "  - MySQL/MariaDB:"
  echo -e "    * Benutzername: ${PMA_USERNAME}"
  echo -e "    * Passwort: ${MYSQL_ROOT_PASSWORD}"
else
  echo -e "  - TxAdmin: http://${SERVER_IP}:40120"
  if [ "$TXADMIN_CONFIGURED" = true ]; then
    echo -e "  - TxAdmin ist bereits konfiguriert. Verwenden Sie Ihre bestehenden Anmeldedaten."
  elif [ -n "$TXADMIN_PIN" ]; then
    echo -e "  - TxAdmin PIN: ${TXADMIN_PIN} (falls TxAdmin neu initialisiert wurde)"
  else
    echo -e "  - Falls TxAdmin neu initialisiert wurde, für sofortigen PIN:"
    echo -e "    ${BLUE}systemctl stop fivem.service && cd /opt/fivem && ./run.sh +set serverProfile default +set txAdminPort 40120${NC}"
  fi
  echo -e "  - FiveM wurde erfolgreich aktualisiert."
fi

echo ""
echo -e "${YELLOW}Wichtige Informationen:${NC}"
echo -e "  1. Richten Sie Ihren FiveM-Server über das TxAdmin-Panel ein."
echo -e "  2. Der FiveM-Server läuft als Systemdienst. Verwenden Sie folgende Befehle zur Steuerung:"
echo -e "     - Status prüfen: systemctl status fivem"
echo -e "     - Neustarten: systemctl restart fivem"
echo -e "     - Stoppen: systemctl stop fivem"
echo -e "     - Starten: systemctl start fivem"
echo -e "  3. Für sofortige PIN-Erfassung bei Problemen:"
echo -e "     ${BLUE}systemctl stop fivem.service && cd /opt/fivem && timeout 30 ./run.sh +set serverProfile default +set txAdminPort 40120 | grep PIN${NC}"
echo ""
echo -e "${GREEN}Viel Spaß mit Ihrem FiveM-Server!${NC}"

# Speichere die Zugangsdaten in einer Datei
if [ "$action_choice" -eq "1" ]; then
  echo -e "TxAdmin: http://${SERVER_IP}:40120" > /root/fivem_credentials.txt
  if [ -n "$TXADMIN_PIN" ]; then
    echo -e "TxAdmin PIN: ${TXADMIN_PIN}" >> /root/fivem_credentials.txt
  fi
  echo -e "phpMyAdmin: http://${SERVER_IP}/phpmyadmin" >> /root/fivem_credentials.txt
  echo -e "MySQL/MariaDB Benutzername: ${PMA_USERNAME}" >> /root/fivem_credentials.txt
  echo -e "MySQL/MariaDB Passwort: ${MYSQL_ROOT_PASSWORD}" >> /root/fivem_credentials.txt
  echo -e "\n${GREEN}Zugangsdaten wurden in /root/fivem_credentials.txt gespeichert.${NC}"
fi

# Für sofortige PIN-Erfassung bei Bedarf entkommentieren:
# show_pin_immediately