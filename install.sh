#!/bin/bash
# Script de Instalação Seguro para RustyProxy (v2.1 - Otimizado)

# Configurações
TEMP_DIR=$(mktemp -d)
LOG_FILE="/var/log/rustyproxy_install.log"
INSTALL_DIR="/opt/rustyproxy"
REPO_URL="https://github.com/WorldSsh/RustyProxyOnly.git"
RUSTUP_URL="https://sh.rustup.rs"
RUSTUP_SHA256="a2806d9c2ce34306d4d5a9b80169f1deb1f9544d07b1f233846f3c81786a0d38"  # Atualizar conforme necessário

# Cores para mensagens
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# Funções auxiliares
error_exit() {
    echo -e "\n${RED}${BOLD}ERRO:${RESET} $1"
    echo "Consulte o log em: ${YELLOW}${LOG_FILE}${RESET}" >&2
    exit 1
}

log_step() {
    echo -e "\n${BLUE}${BOLD}>>> $1${RESET}"
    echo -e "$(date): $1" >> "$LOG_FILE"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error_exit "Este script precisa ser executado como root!"
    fi
}

cleanup() {
    rm -rf "$TEMP_DIR"
    log_step "Arquivos temporários limpos."
}

install_dependencies() {
    log_step "Instalando dependências do sistema..."
    export DEBIAN_FRONTEND=noninteractive

    apt-get update >> "$LOG_FILE" 2>&1 || error_exit "Não foi possível atualizar os repositórios."

    dependencies=(
        lsb-release
        curl
        build-essential
        git
        pkg-config
        libssl-dev
    )

    apt-get install -y "${dependencies[@]}" >> "$LOG_FILE" 2>&1 || error_exit "Erro na instalação de dependências."
}

verify_system() {
    log_step "Verificando compatibilidade do sistema..."

    os_info=$(lsb_release -is 2>/dev/null || error_exit "lsb_release não encontrado.")
    version_info=$(lsb_release -rs)

    case "$os_info" in
        Ubuntu)
            [[ "$version_info" =~ ^(18|20|22|24)\. ]] || error_exit "Versão do Ubuntu não suportada: $version_info."
            ;;
        Debian)
            [[ "$version_info" =~ ^(9|10|11|12) ]] || error_exit "Versão do Debian não suportada: $version_info."
            ;;
        *)
            error_exit "Sistema Operacional não suportado: $os_info."
            ;;
    esac
}

install_rust() {
    log_step "Instalando Rust Toolchain..."

    if ! command -v rustc &> /dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf "$RUSTUP_URL" -o "$TEMP_DIR/rustup.sh" || error_exit "Erro ao baixar Rustup."
        echo "$RUSTUP_SHA256  $TEMP_DIR/rustup.sh" | sha256sum -c - >> "$LOG_FILE" 2>&1 || error_exit "Checksum inválido do Rustup."
        sh "$TEMP_DIR/rustup.sh" -y --no-modify-path >> "$LOG_FILE" 2>&1 || error_exit "Erro na instalação do Rust."
        source "/root/.cargo/env" || error_exit "Falha ao configurar o ambiente Rust."
    else
        log_step "Rust já está instalado."
    fi
}

compile_rustyproxy() {
    log_step "Compilando RustyProxy..."

    git clone --branch "main" "$REPO_URL" "$TEMP_DIR/RustyProxyOnly" >> "$LOG_FILE" 2>&1 || error_exit "Erro ao clonar repositório."

    mkdir -p "$INSTALL_DIR" || error_exit "Não foi possível criar o diretório de instalação."

    (
        cd "$TEMP_DIR/RustyProxyOnly/RustyProxy" || error_exit "Diretório do projeto não encontrado."
        cargo build --release --jobs $(nproc) >> "$LOG_FILE" 2>&1 || error_exit "Erro na compilação."
        mv ./target/release/RustyProxy "$INSTALL_DIR/proxy" || error_exit "Erro ao mover binário RustyProxy."
        mv "$TEMP_DIR/RustyProxyOnly/menu.sh" "$INSTALL_DIR/menu" || error_exit "Erro ao mover script do menu."
    )
}

setup_permissions() {
    log_step "Configurando permissões..."

    chmod -R 750 "$INSTALL_DIR" || error_exit "Erro ao ajustar permissões."
    chown -R root:root "$INSTALL_DIR" || error_exit "Erro ao definir proprietário."
    ln -sf "$INSTALL_DIR/menu" "/usr/local/bin/rustyproxy" || error_exit "Erro ao criar link simbólico."
}

show_success() {
    clear
    echo -e "\n${GREEN}${BOLD}Instalação concluída com sucesso!${RESET}"
    echo -e "\nUse o comando: ${BOLD}rustyproxy${RESET} para executar."
}

uninstall() {
    log_step "Desinstalando RustyProxy..."

    rm -rf "$INSTALL_DIR" || error_exit "Erro ao remover diretório de instalação."
    rm -f "/usr/local/bin/rustyproxy" || error_exit "Erro ao remover link simbólico."

    echo -e "\n${GREEN}RustyProxy foi desinstalado com sucesso.${RESET}"
}

# Fluxo principal
trap cleanup EXIT

case "$1" in
    --uninstall)
        check_root
        uninstall
        ;;
    *)
        check_root
        install_dependencies
        verify_system
        install_rust
        compile_rustyproxy
        setup_permissions
        show_success
        ;;
esac
