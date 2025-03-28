#!/bin/bash

PORTS_FILE="/opt/rustyproxy/ports"

# Função para verificar se uma porta está em uso
is_port_in_use() {
    local port=$1
    
    if netstat -tuln 2>/dev/null | grep -q ":$port\b" || \
       ss -tuln 2>/dev/null | grep -q ":$port\b"; then
        return 0
    else
        return 1
    fi
}

# Função para abrir uma porta de proxy
add_proxy_port() {
    local port=$1
    local status=${2:-"@RustyProxy"}

    if is_port_in_use $port; then
        echo "[ERRO] A porta $port já está em uso."
        return
    fi

    local command="/opt/rustyproxy/proxy --port $port --status $status"
    local service_file_path="/etc/systemd/system/proxy${port}.service"
    local service_file_content="[Unit]
Description=RustyProxy${port}
After=network.target

[Service]
LimitNOFILE=infinity
LimitNPROC=infinity
LimitMEMLOCK=infinity
LimitSTACK=infinity
LimitCORE=0
LimitAS=infinity
LimitRSS=infinity
LimitCPU=infinity
LimitFSIZE=infinity
Type=simple
ExecStart=${command}
Restart=always

[Install]
WantedBy=multi-user.target"

    echo "$service_file_content" | sudo tee "$service_file_path" > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable "proxy${port}.service"
    sudo systemctl start "proxy${port}.service"

    if ! grep -qx "$port" "$PORTS_FILE"; then
        echo $port >> "$PORTS_FILE"
    fi
    echo "[SUCESSO] Porta $port aberta com sucesso."
}

# Função para fechar uma porta de proxy
del_proxy_port() {
    local port=$1

    sudo systemctl disable "proxy${port}.service" --now
    sudo rm -f "/etc/systemd/system/proxy${port}.service"
    sudo systemctl daemon-reload

    sed -i "/^$port$/d" "$PORTS_FILE"
    echo "[SUCESSO] Porta $port fechada com sucesso."
}

# Função para desinstalar o RustyProxy
uninstall_rustyproxy() {
    echo "[INFO] Desinstalando o RustyProxy..."

    # Parar e remover todos os serviços
    if [ -s "$PORTS_FILE" ]; then
        while read -r port; do
            del_proxy_port $port
        done < "$PORTS_FILE"
    fi

    # Remover binário, arquivos e diretórios
    sudo rm -rf /opt/rustyproxy
    sudo rm -f "$PORTS_FILE"

    echo "[SUCESSO] RustyProxy desinstalado com sucesso."
}

# Função para exibir o menu formatado
show_menu() {
    clear
    tput setaf 4; echo "--------------------------------------------------------------"
    tput setab 4; tput bold; tput setaf 7; echo "                   ⚒ RUSTY PROXY MANAGER ⚒                   "
    tput sgr0; tput setaf 4; echo "--------------------------------------------------------------"
    
    if [ ! -s "$PORTS_FILE" ]; then
        printf " PORTAS ATIVAS: %-34s\n" "NENHUMA"
    else
        printf " PORTAS:"
        while read -r port; do
            printf " %-5s" "$port"
        done < "$PORTS_FILE"
        echo
    fi

    tput setaf 4; echo "--------------------------------------------------------------"
    tput setaf 1; echo "[01]"; tput setaf 3; echo "ABRIR PORTAS"
    tput setaf 1; echo "[02]"; tput setaf 3; echo "FECHAR PORTAS"
    tput setaf 1; echo "[03]"; tput setaf 3; echo "DESINSTALAR RUSTYPROXY"
    tput setaf 1; echo "[00]"; tput setaf 3; echo "SAIR"
    tput setaf 4; echo "--------------------------------------------------------------"
    tput sgr0
    read -p "  O QUE DESEJA FAZER ?: " option

    case $option in
        1)
            clear
            read -p "DIGITE A PORTA: " port
            while ! [[ $port =~ ^[0-9]+$ ]]; do
                echo "[ERRO] DIGITE UMA PORTA VÁLIDA."
                read -p "DIGITE A PORTA: " port
            done
            read -p "DIGITE O STATUS DE CONEXÃO (DEIXE VAZIO PARA PADRÃO): " status
            add_proxy_port $port "$status"
            read -p "Pressione qualquer tecla para voltar ao menu..." dummy
            ;;
        2)
            clear
            read -p "DIGITE A PORTA: " port
            while ! [[ $port =~ ^[0-9]+$ ]]; do
                echo "[ERRO] DIGITE UMA PORTA VÁLIDA."
                read -p "DIGITE A PORTA: " port
            done
            del_proxy_port $port
            read -p "Pressione qualquer tecla para voltar ao menu..." dummy
            ;;
        3)
            clear
            uninstall_rustyproxy
            read -p "Pressione qualquer tecla para sair..." dummy
            exit 0
            ;;
        0)
            exit 0
            ;;
        *)
            echo "[ERRO] OPÇÃO INVÁLIDA."
            read -p "Pressione qualquer tecla para voltar ao menu..." dummy
            ;;
    esac
}

# Verificar se o arquivo de portas existe, caso contrário, criar
if [ ! -f "$PORTS_FILE" ]; then
    sudo touch "$PORTS_FILE"
fi

# Loop do menu
while true; do
    show_menu
done
