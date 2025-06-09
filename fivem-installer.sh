#!/bin/bash

red="\e[0;91m"
green="\e[0;92m"
bold="\e[1m"
reset="\e[0m"

if [ "$EUID" -ne 0 ]; then
    echo -e "${red}Please run as root${reset}"
    exit 1
fi

# Funktion zur Anzeige von Statusmeldungen
status() {
    clear
    echo -e "${green}$@...${reset}"
    sleep 1
}

# Funktion zum Ausführen von Befehlen mit Fehlerbehandlung
runCommand() {
    COMMAND="$1
    if [[ -n "$2" ]]; then
        status "$2"
    fi
    eval "$COMMAND"
    BASH_CODE=$?
    if [ $BASH_CODE -ne 0 ]; then
        echo -e "${red}Error: ${COMMAND} returned $BASH_CODE${reset}"
        exit $BASH_CODE
    fi
}

# Funktion zur Überprüfung von whiptail
ensure_whiptail() {
    if ! command -v whiptail &>/dev/null; then
        status "Installing whiptail"
        runCommand "apt update && apt install -y whiptail"
    fi
}

dir=/home/FiveM
update_artifacts=false
non_interactive=false
artifacts_version=0
kill_txAdmin=false
delete_dir=false
txadmin_deployment=true
install_phpmyadmin=false
crontab_autostart=false
pma_options=()

# Funktion zur Versionsauswahl mit Whiptail
selectVersion() {
    readarray -t VERSIONS <<< "$(curl -s https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/ | grep -m 3 -o '[0-9].*/fx.tar.xz')"
    latest_recommended=$(echo "${VERSIONS[0]}" | cut -d'-' -f1)
    latest=$(echo "${VERSIONS[2]}" | cut -d'-' -f1)

    if [[ "${artifacts_version}" == "0" ]]; then
        if [[ "${non_interactive}" == "false" ]]; then
            ensure_whiptail
            status=$(whiptail --title "Select Runtime Version" --menu "Choose a FiveM runtime version:" 15 50 4 \
                "1" "Latest version -> $latest" \
                "2" "Latest recommended version -> $latest_recommended" \
                "3" "Choose custom version" \
                "4" "Do nothing" 3>&1 1>&2 2>&3)
            exitstatus=$?
            if [ $exitstatus -ne 0 ]; then
                exit 0
            fi

            case $choice in
                1)
                    artifacts_version="https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/${VERSIONS[2]}"
                    ;;
                2)
                    artifacts_version="https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/${VERSIONS[0]}"
                    ;;
                3)
                    artifacts_version=$(whiptail --title "Custom Version" --inputbox "Enter the download link:" 10 50 3>&1 1>&2 2>&3)
                    if [ $? -ne 0 ]; then
                        exit 0
                    fi
                    ;;
                4)
                    exit 0
                    ;;
            esac
            return
        else
            artifacts_version="latest"
        fi
    fi
    if [[ "${artifacts_version}" == "latest" ]]; then
        artifacts_version="https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/${VERSIONS[2]}"
    fi
}

# Funktion zur Überprüfung des Ports mit Whiptail für Benutzerinteraktion
checkPort() {
    lsof -i :40120
    if [[ $? == 0 ]]; then
        if [[ "${non_interactive}" == "false" ]]; then
            if [[ "${kill_txAdmin}" == "false" ]]; then
                ensure_whiptail
                if whiptail --title "Port Conflict" --yesno "Something is running on port 40120. Kill the process?" 10 50; then
                    kill_txAdmin="true"
                else
                    exit 0
                fi
            fi
        fi
        if [[ "${kill_txAdmin}" == "true" ]]; then
            status "Killing process on port 40120"
            runCommand "apt install -y psmisc"
            runCommand "fuser -k 40120/tcp"
            return
        fi
        echo -e "${red}Error: Port 40120 is already in use.${reset}"
        exit 1
    fi
}

# Funktion zur Überprüfung des Verzeichnisses mit Whiptail
checkDir() {
    if [[ -e $dir ]]; then
        if [[ "${non_interactive}" == "false" ]]; then
            if [[ "${delete_dir}" == "false" ]]; then
                ensure_whiptail
                if whiptail --title "Directory Exists" --yesno "Directory $dir exists. Remove it?" 10 50; then
                    delete_dir="true"
                else
                    exit 0
                fi
            fi
        fi
        if [[ "${delete_dir}" == "true" ]]; then
            status "Deleting $dir"
            runCommand "rm -r $dir"
            return
        fi
        echo -e "${red}Error: Directory $dir already exists.${reset}"
        exit 1
    fi
}

# Funktion zur Auswahl des Deployment-Typs mit Whiptail
selectDeployment() {
    if [[ "${txadmin_deployment}" == "0" ]]; then
        txadmin_deployment="true"
        if [[ "${non_interactive}" == "false" ]]; then
            ensure_whiptail
            choice=$(whiptail --title "Select Deployment Type" --menu "Choose deployment type:" 15 50 3 \
                "1" "Install template via TxAdmin" \
                "2" "Use cfx-server-data" \
                "3" "Do nothing" 3>&1 1>&2 2>&3)
            exitstatus=$?
            if [ $exitstatus -ne 0 ]; then
                exit 0
            fi
            case $choice in
                1)
                    txadmin_deployment="true"
                    ;;
                2)
                    txadmin_deployment="false"
                    ;;
                3)
                    exit 0
                    ;;
            esac
        fi
    fi
    if [[ "${txadmin_deployment}" == "false" ]]; then
        examServData
    fi
}

# Funktion zur Crontab-Erstellung mit Whiptail
createCrontab() {
    if [[ "${crontab_autostart}" == "0" ]]; then
        crontab_autostart="false"
        if [[ "${non_interactive}" == "false" ]]; then
            ensure_whiptail
            if whiptail --title "Crontab Autostart" --yesno "Create crontab to autostart TxAdmin?" 10 50; then
                crontab_autostart="true"
            fi
        fi
    fi
    if [[ "${crontab_autostart}" == "true" ]]; then
        status "Creating crontab entry"
        runCommand "echo \"@reboot root /bin/bash /home/FiveM/start.sh\" > /etc/cron.d/fivem"
    fi
}

# Funktion zur Installation von PHPMyAdmin mit Whiptail
installPma() {
    if [[ "${non_interactive}" == "false" ]]; then
        if [[ "${install_phpmyadmin}" == "0" ]]; then
            ensure_whiptail
            if whiptail --title "Install MariaDB/PHPMyAdmin" --yesno "Install MariaDB/MySQL and PHPMyAdmin?" 10 50; then
                install_phpmyadmin="true"
            else
                install_phpmyadmin="false"
            fi
        fi
    fi
    if [[ "${install_phpmyadmin}" == "true" ]]; then
        runCommand "bash <(curl -s https://raw.githubusercontent.com/JulianGransee/PHPMyAdminInstaller/main/install.sh) -s ${pma_options[*]}"
    fi
}

# Hauptinstallationsfunktion (unverändert bis auf Whiptail-Integration)
install() {
    runCommand "apt update -y" "Updating"
    runCommand "apt install -y wget git curl dos2unix net-tools sed screen xz-utils lsof" "Installing necessary packages"

    checkPort
    checkDir
    selectDeployment
    selectVersion
    createCrontab
    installPma

    runCommand "mkdir -p $dir/server" "Creating directories for the FiveM server"
    runCommand "cd $dir/server/"

    runCommand "wget $artifacts_version" "Downloading FxServer"
    runCommand "tar xf fx.tar.xz" "Unpacking FxServer archive"
    runCommand "rm fx.tar.xz"

    status "Creating start, stop, and access scripts"
    cat << EOF > $dir/start.sh
#!/bin/bash
red="\e[0;91m"
green="\e[0;92m"
bold="\e[1m"
reset="\e[0m"
port=\$(lsof -Pi :40120 -sTCP:LISTEN -t)
if [ -z "\$port" ]; then
    screen -dmS fivem sh $dir/server/run.sh
    echo -e "\n\${green}TxAdmin was started!\${reset}"
else
    echo -e "\n\${red}The default \${reset}\${bold}TxAdmin\${reset}\${red} port is already in use -> Is a \${reset}\${bold}FiveM Server\${reset}\${red} already running?\${reset}"
fi
EOF
    runCommand "chmod +x $dir/start.sh"

    runCommand "echo \"screen -xS fivem\" > $dir/attach.sh"
    runCommand "chmod +x $dir/attach.sh"

    runCommand "echo \"screen -XS fivem quit\" > $dir/stop.sh"
    runCommand "chmod +x $dir/stop.sh"

    port=$(lsof -Pi :40120 -sTCP:LISTEN -t)
    if [[ -z "$port" ]]; then
        if [[ -e '/tmp/fivem.log' ]]; then
            rm /tmp/fivem.log
        fi
        screen -L -Logfile /tmp/fivem.log -dmS fivem $dir/server/run.sh

        sleep 2

        line_counter=0
        while true; do
            while read -r line; do
                echo "$line"
                if [[ "$line" == *"able to access"* ]]; then
                    break 2
                fi
            done < /tmp/fivem.log
            sleep 1
        done

        cat -v /tmp/fivem.log > /tmp/fivem.log.tmp
        while read -r line; do
            if [[ "$line" == *"PIN"* ]]; then
                let "line_counter += 2"
                break
            fi
            let "line_counter += 1"
        done < /tmp/fivem.log.tmp

        pin_line=$(head -n $line_counter /tmp/fivem.log | tail -n +$line_counter)
        echo "$pin_line" > /tmp/fivem.log.tmp
        pin=$(cat -v /tmp/fivem.log.tmp | sed --regexp-extended --expression='s/\^\[\[([0-9][0-9][a-z])|([0-9][a-z])|(\^\[\[)|(\[.*\])|(M-bM-\^TM-\^C)|(\^M)//g')
        pin=$(echo "$pin" | sed --regexp-extended --expression='s/[\ ]//g')

        rm /tmp/fivem.log.tmp
        clear

        echo -e "\n${green}${bold}TxAdmin${reset}${green} was started successfully${reset}"
        txadmin="http://$(ip route get 1.1.1.1 | awk '{print $7; exit}'):40120"
        echo -e "\n\n${red}${bold}Commands for SSH use:${reset}"
        echo -e "${red}To ${reset}${blue}start${reset}${red} TxAdmin: ${reset}${bold}sh $dir/start.sh${reset}"
        echo -e "${red}To ${reset}${blue}stop${reset}${red} TxAdmin: ${reset}${bold}sh $dir/stop.sh${reset}"
        echo -e "${red}To view ${reset}${blue}Live Console${reset}${red}: ${reset}${bold}sh $dir/attach.sh${reset}"

        echo -e "\n${green}TxAdmin Web Interface: ${reset}${blue}${txadmin}${reset}"
        echo -e "${green}Pin: ${reset}${blue}${pin:(-4)}${reset}${green} (use within 5 minutes!)${reset}"
        echo -e "\n${green}Server Data Path: ${reset}${blue}$dir/server-data${reset}"

        if [[ "$install_phpmyadmin" == "true" ]]; then
            echo
            echo "MariaDB and PHPMyAdmin data:"
            runCommand "cat /root/.mariadbPhpma"
            runCommand "rm /root/.mariadbPhpma"
            rootPasswordMariaDB=$(cat /root/.mariadbRoot)
            rm /root/.mariadbRoot
            fivempasswd=$(pwgen 32 1)
            mariadb -u root -p"$rootPasswordMariaDB" -e "CREATE DATABASE fivem;"
            mariadb -u root -p"$rootPasswordMariaDB" -e "GRANT ALL PRIVILEGES ON fivem.* TO 'fivem'@'localhost' IDENTIFIED BY '${fivempasswd}';"
            echo "
FiveM MySQL Data:
    User: fivem
    Password: ${fivempasswd}
    Database name: fivem
    FiveM MySQL Connection String:
        set mysql_connection_string \"server=127.0.0.1;database=fivem;userid=fivem;password=${fivempasswd}\""
            runCommand "cat /root/.PHPma"
        fi
        sleep 1
    else
        echo -e "\n${red}Port 40120 is already in use. Is a FiveM server running?${reset}"
    fi
}

# Update-Funktion mit Whiptail für Verzeichnisauswahl
update() {
    selectVersion
    if [[ "${non_interactive}" == "false" ]]; then
        ensure_whiptail
        readarray -t directories <<<"$(find / -name "alpine")"
        if [ ${#directories[@]} -eq 0 ]; then
            echo -e "${red}Error: No alpine directories found.${reset}"
            exit 1
        fi
        menu_options=()
        for i in "${!directories[@]}"; do
            menu_options+=("$((i+1))" "${directories[$i]}")
        done
        choice=$(whiptail --title "Select Alpine Directory" --menu "Choose the alpine directory:" 15 50 ${#directories[@]} "${menu_options[@]}" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            exit 0
        fi
        dir="${directories[$((choice-1))]}/.."
    else
        if [[ "$update_artifacts" == "false" ]]; then
            echo -e "${red}Error: Directory must be specified in non-interactive mode using --update <path>.${reset}"
            exit 1
        fi
        dir=$update_artifacts
    fi

    checkPort
    runCommand "rm -rf $dir/alpine" "Deleting alpine"
    runCommand "rm -f $dir/run.sh" "Deleting run.sh"
    runCommand "wget --directory-prefix=$dir $artifacts_version" "Downloading fx.tar.xz"
    echo "${green}Success${reset}"
    runCommand "tar xf $dir/fx.tar.xz -C $dir" "Unpacking fx.tar.xz"
    echo "${green}Success${reset}"
    runCommand "rm -r $dir/fx.tar.xz" "Deleting fx.tar.xz"
    clear
    echo "${green}Update successful${reset}"
    exit 0
}

# Hauptfunktion mit Whiptail für die Hauptauswahl
main() {
    if ! command -v curl &>/dev/null; then
        runCommand "apt update -y && apt install -y curl"
    fi
    clear

    if [[ "${non_interactive}" == "false" ]]; then
        ensure_whiptail
        choice=$(whiptail --title "FiveM Installer" --menu "Choose an action:" 15 50 3 \
            "1" "Install FiveM" \
            "2" "Update FiveM" \
            "3" "Do nothing" 3>&1 1>&2 2>&3)
        exitstatus=$?
        if [ $exitstatus -ne 0 ]; then
            exit 0
        fi
        case $choice in
            1)
                install
                ;;
            2)
                update
                ;;
            3)
                exit 0
                ;;
        esac
    else
        if [[ "${update_artifacts}" == "false" ]]; then
            install
        else
            update
        fi
    fi
}

# Argument-Parsing (unverändert)
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo -e "${bold}Usage: bash <(curl -s https://raw.githubusercontent.com/Twe3x/fivem-installer/main/setup.sh) [OPTIONS]${reset}"
            echo "Options:"
            echo "  -h, --help                      Display this help message."
            echo "      --non-interactive           Skip all interactive prompts."
            echo "  -v, --version <URL|latest>      Choose an artifacts version (default: latest)."
            echo "  -u, --update <path>             Update artifacts at the specified path."
            echo "      --no-txadmin                Disable TxAdmin and use cfx-server-data."
            echo "  -c, --crontab                   Enable crontab autostart."
            echo "      --kill-port                 Kill process on port 40120."
            echo "      --delete-dir                Delete /home/FiveM directory if it exists."
            echo "  -p, --phpmyadmin                Enable PHPMyAdmin installation."
            echo "      --db_user <name>            Specify database user."
            echo "      --db_password <password>    Set database password."
            echo "      --generate_password         Generate a secure database password."
            echo "      --reset_password            Reset database password."
            echo "      --remove_db                 Reinstall MySQL/MariaDB."
            echo "      --remove_pma                Reinstall PHPMyAdmin."
            exit 0
            ;;
        --non-interactive)
            non_interactive=true
            pma_options+=("--non-interactive")
            shift
            ;;
        -v|--version)
            artifacts_version="$2"
            shift 2
            ;;
        -u|--update)
            update_artifacts="$2"
            shift 2
            ;;
        --no-txadmin)
            txadmin_deployment=false
            shift
            ;;
        -p|--phpmyadmin)
            install_phpmyadmin=true
            shift
            ;;
        -c|--crontab)
            crontab_autostart=true
            shift
            ;;
        --kill-port)
            kill_txAdmin=true
            shift
            ;;
        --delete-dir)
            delete_dir=true
            shift
            ;;
        --security)
            pma_options+=("--security")
            shift
            ;;
        --simple)
            pma_options+=("--simple")
            shift
            ;;
        --db_user)
            pma_options+=("--db_user $2")
            shift 2
            ;;
        --db_password)
            pma_options+=("--db_password $2")
            shift 2
            ;;
        --generate_password)
            pma_options+=("--generate_password")
            shift
            ;;
        --reset_password)
            pma_options+=("--reset_password")
            shift
            ;;
        --remove_db)
            pma_options+=("--remove_db")
            shift
            ;;
        --remove_pma)
            pma_options+=("--remove_pma")
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validierung der PHPMyAdmin-Optionen (unverändert)
if [[ "${non_interactive}" == "true" && "${install_phpmyadmin}" == "true" ]]; then
    errors=()
    if ! printf "%s\n" "${pma_options[@]}" | grep -q -- "--security" &&
       ! printf "%s\n" "${pma_options[@]}" | grep -q -- "--simple"; then
        errors+=("${red}Error:${reset} With --non-interactive, either --security or --simple must be set.")
    fi
    if printf "%s\n" "${pma_options[@]}" | grep -q -- "--security"; then
        if ! printf "%s\n" "${pma_options[@]}" | grep -q -- "--db_user"; then
            errors+=("${red}Error:${reset} With --non-interactive and --security, --db_user <user> must be set.")
        fi
        if ! printf "%s\n" "${pma_options[@]}" | grep -q -- "--db_password" &&
           ! printf "%s\n" "${pma_options[@]}" | grep -q -- "--generate_password"; then
            errors+=("${red}Error:${reset} With --non-interactive and --security, either --db_password <password> or --generate_password must be set.")
        fi
    fi
    if [[ ${#errors[@]} -gt 0 ]]; then
        for error in "${errors[@]}"; do
            echo -e "$error"
        done
        exit 1
    fi
fi

main