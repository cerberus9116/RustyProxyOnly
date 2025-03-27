#!/bin/bash
# rustyproxy Installer

TOTAL_STEPS=9
CURRENT_STEP=0

show_progress() {
    PERCENT=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo "Progresso: [${PERCENT}%] - $1"
}

error_exit() {
    echo -e "\nErro: $1"
    exit 1
}

increment_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
}

if [ "$EUID" -ne 0 ]; then
    error_exit "EXECUTE COMO ROOT"
else
    clear
    echo ""
    echo -e "\033[0;32m  █▀█ █░█ █▀ ▀█▀ █▄█  █▀▄▀█ ▄▀█ █▄░█ ▄▀█ █▀▀ █▀▀ █▀█
    █▀▄ █▄█ ▄█ ░█░ ░█░  █░▀░█ █▀█ █░▀█ █▀█ █▄█ ██▄ █▀▄ 
    By:@𝗨𝗟𝗘𝗞𝗕𝗥 Edi:@𝗝𝗘𝗙𝗙𝗦𝗦𝗛"
    echo -e " "
    show_progress "Atualizando repositorios..."
    export DEBIAN_FRONTEND=noninteractive
    apt update -y > /dev/null 2>&1 || error_exit "Falha ao atualizar os repositorios"
    increment_step

    # ---->>>> Verificação do sistema
    show_progress "Verificando o sistema..."
    if ! command -v lsb_release &> /dev/null; then
        apt install lsb-release -y > /dev/null 2>&1 || error_exit "Falha ao instalar lsb-release"
    fi
    increment_step

    # ---->>>> Verificação do sistema
    OS_NAME=$(lsb_release -is)
    VERSION=$(lsb_release -rs)

    case $OS_NAME in
        Ubuntu)
            case $VERSION in
                24.*|22.*|20.*|18.*)
                    show_progress "Sistema Ubuntu suportado, continuando..."
                    ;;
                *)
                    error_exit "Versão do Ubuntu não suportada. Use 18, 20, 22 ou 24."
                    ;;
            esac
            ;;
        Debian)
            case $VERSION in
                12*|11*|10*|9*)
                    show_progress "Sistema Debian suportado, continuando..."
                    ;;
                *)
                    error_exit "Versão do Debian não suportada. Use 9, 10, 11 ou 12."
                    ;;
            esac
            ;;
        *)
            error_exit "Sistema não suportado. Use Ubuntu ou Debian."
            ;;
    esac
    increment_step

    # ---->>>> Instalação de pacotes requisitos e atualização do sistema
    show_progress "Atualizando o sistema..."
    apt upgrade -y > /dev/null 2>&1 || error_exit "Falha ao atualizar o sistema"
    apt-get install curl build-essential git -y > /dev/null 2>&1 || error_exit "Falha ao instalar pacotes"
    increment_step

    # ---->>>> Criando o diretório do script
    show_progress "Criando diretorio /opt/rustyproxy..."
    mkdir -p /opt/rustyproxy > /dev/null 2>&1
    increment_step

    # ---->>>> Instalar rust
    show_progress "Instalando Rust..."
    if ! command -v rustc &> /dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y > /dev/null 2>&1 || error_exit "Falha ao instalar Rust"
        source "$HOME/.cargo/env"
    fi
    increment_step

    # ---->>>> Instalar o RustyProxy
    show_progress "Compilando RustyProxy, isso pode levar algum tempo dependendo da maquina..."

    if [ -d "/root/RustyProxyOnly" ]; then
        rm -rf /root/RustyProxyOnly
    fi


    git clone --branch "main" https://github.com/WorldSsh/RustyProxyOnly.git /root/RustyProxyOnly > /dev/null 2>&1 || error_exit "Falha ao clonar rustyproxy"
    mv /root/RustyProxyOnly/menu.sh /opt/rustyproxy/menu
    cd /root/RustyProxyOnly/RustyProxy
    cargo build --release --jobs $(nproc) > /dev/null 2>&1 || error_exit "Falha ao compilar rustyproxy"
    mv ./target/release/RustyProxy /opt/rustyproxy/proxy
    increment_step

    # ---->>>> Configuração de permissões
    show_progress "Configurando permissões..."
    chmod +x /opt/rustyproxy/proxy
    chmod +x /opt/rustyproxy/menu
    ln -sf /opt/rustyproxy/menu /usr/local/bin/rustyproxy
    increment_step

    # ---->>>> Limpeza
    show_progress "Limpando diretórios temporários..."
    cd /root/
    rm -rf /root/RustyProxyOnly/
    increment_step

    # ---->>>> Instalação finalizada :)
    clear
echo -e "\033[1;37m════════════════════════════════════════════════════\033[0m"
tput setaf 7 ; tput setab 4 ; tput bold ; printf '%40s%s%-12s\n' "SEJA MUITO BEM VINDO (A)" ; tput sgr0
echo -e "\033[1;37m════════════════════════════════════════════════════\033[0m"
echo ""
echo -e "                  \033[1;31m ⚠️ ATENÇÃO ⚠️\033[0m"
echo -e "      \033[1;33mPARA ACESSAR O MENU DIGITE 'rustyproxy' !\033[0m"
fi
