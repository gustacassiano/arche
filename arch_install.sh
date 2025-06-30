#!/bin/bash
# Script de instalação automatizada do Arch Linux
# ATENÇÃO: Leia e adapte conforme seu hardware e necessidades!
# Execute a partir do live ISO do Arch Linux

set -e

# Verificar se fzf está instalado, se não instalar
if ! command -v fzf &> /dev/null; then
    echo "fzf não encontrado. Instalando..."
    pacman -Sy --noconfirm fzf
fi

echo "\n==> Selecione o disco para particionamento (ATENÇÃO: TODOS OS DADOS SERÃO APAGADOS!)"
disco=$(lsblk -d -n -o NAME,SIZE | fzf --prompt="Selecione o disco: " | awk '{print $1}')
if [ -z "$disco" ]; then
    echo "Nenhum disco selecionado. Abortando."
    exit 1
fi
disco="/dev/$disco"
echo "Disco selecionado: $disco"

# 1. Configuração inicial
loadkeys br-abnt2  # Altere para seu layout, se necessário
echo "Teclado configurado para ABNT2 (pt-br)."

# 2. Verificar modo de boot
if [ -d /sys/firmware/efi ]; then
    echo "Boot em modo UEFI."
else
    echo "Boot em modo BIOS/Legacy."
fi

# 3. Conectar à internet (usuário deve garantir conexão)
echo "Verificando conexão de rede..."
if ping -c 1 archlinux.org &>/dev/null; then
    echo "Conexão OK."
else
    echo "Sem conexão. Configure manualmente (iwctl, etc) e execute novamente."
    exit 1
fi

# 4. Sincronizar relógio
timedatectl set-ntp true
echo "Relógio sincronizado."

# Detectar RAM disponível para sugestão de swap
ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
ram_gb=$(( (ram_kb + 1048575) / 1048576 ))
if [ $ram_gb -gt 8 ]; then
    swap_sug=8
else
    swap_sug=$ram_gb
fi
swap_sug_mib=$((swap_sug * 1024))

# Sugerir tamanho EFI/boot
boot_sug_mib=1024

# Perguntar se quer partição /home separada
read -p "Deseja criar uma partição /home separada? (s/N): " home_sep
if [[ $home_sep == "s" || $home_sep == "S" ]]; then
    home_sep=true
else
    home_sep=false
fi

# Perguntar se quer swap
read -p "Deseja criar swap? (S/n): " swap_opt
if [[ $swap_opt == "n" || $swap_opt == "N" ]]; then
    swap_enable=false
else
    swap_enable=true
    read -p "Tipo de swap: partição (p) ou swapfile (f)? [p/f]: " swap_type
    swap_type=${swap_type:-p}
fi

# Perguntar se quer LUKS
read -p "Deseja criptografar a partição root com LUKS? (s/N): " luks_opt
if [[ $luks_opt == "s" || $luks_opt == "S" ]]; then
    luks_enable=true
else
    luks_enable=false
fi

# Sugerir tamanhos e permitir customização
read -p "Tamanho da partição EFI/boot em MiB [sugerido: $boot_sug_mib]: " boot_size
boot_size=${boot_size:-$boot_sug_mib}

if $swap_enable; then
    read -p "Tamanho do swap em MiB [sugerido: $swap_sug_mib]: " swap_size
    swap_size=${swap_size:-$swap_sug_mib}
fi

# Calcular espaço restante para root e home
# Obter tamanho total do disco em MiB
size_total=$(lsblk -b -dn -o SIZE $disco)
size_total_mib=$((size_total / 1024 / 1024))

# Reservar espaço para boot e swap
used_mib=$boot_size
if $swap_enable; then
    used_mib=$((used_mib + swap_size))
fi

if $home_sep; then
    # Perguntar tamanho root
    root_sug_mib=20480
    read -p "Tamanho da partição root em MiB [sugerido: $root_sug_mib]: " root_size
    root_size=${root_size:-$root_sug_mib}
    used_mib=$((used_mib + root_size))
    home_size=$((size_total_mib - used_mib))
    read -p "Tamanho da partição home em MiB [sugerido: $home_size]: " home_size_in
    home_size=${home_size_in:-$home_size}
else
    root_size=$((size_total_mib - used_mib))
fi

# Confirmar layout
clear
echo "Resumo do particionamento proposto para $disco:"
echo "EFI/boot: ${boot_size}MiB"
if $swap_enable; then echo "Swap: ${swap_size}MiB"; fi
echo "Root: ${root_size}MiB"
if $home_sep; then echo "Home: ${home_size}MiB"; fi
if $luks_enable; then echo "Criptografia LUKS: ATIVADA"; else echo "Criptografia LUKS: NÃO"; fi
read -p "Deseja continuar com esse layout? (s/N): " confirma
if [[ $confirma != "s" && $confirma != "S" ]]; then
    echo "Operação cancelada."
    exit 1
fi

# Desmontar partições se necessário
dumount $disco* 2>/dev/null || true

# Criar tabela GPT e partições
parted -s $disco mklabel gpt
start=1MiB
end_boot=$((boot_size+1))MiB
parted -s $disco mkpart ESP fat32 $start $end_boot
parted -s $disco set 1 esp on

if $swap_enable && [[ $swap_type == "p" ]]; then
    start_swap=$end_boot
    end_swap=$((boot_size+swap_size+1))MiB
    parted -s $disco mkpart primary linux-swap $start_swap $end_swap
fi

if $home_sep; then
    start_root=$end_swap
    end_root=$((boot_size+swap_size+root_size+1))MiB
    parted -s $disco mkpart primary ext4 $start_root $end_root
    start_home=$end_root
    end_home=$((boot_size+swap_size+root_size+home_size+1))MiB
    parted -s $disco mkpart primary ext4 $start_home 100%
else
    start_root=$end_boot
    end_root=100%
    parted -s $disco mkpart primary ext4 $start_root $end_root
fi

# Descobrir nomes das partições
if [[ $disco == *nvme* ]]; then
    part_efi="${disco}p1"
    idx=2
    if $swap_enable && [[ $swap_type == "p" ]]; then part_swap="${disco}p$idx"; idx=$((idx+1)); fi
    part_root="${disco}p$idx"; idx=$((idx+1))
    if $home_sep; then part_home="${disco}p$idx"; fi
else
    part_efi="${disco}1"
    idx=2
    if $swap_enable && [[ $swap_type == "p" ]]; then part_swap="${disco}$idx"; idx=$((idx+1)); fi
    part_root="${disco}$idx"; idx=$((idx+1))
    if $home_sep; then part_home="${disco}$idx"; fi
fi

# Formatar partições
mkfs.fat -F32 $part_efi
if $swap_enable && [[ $swap_type == "p" ]]; then mkswap $part_swap; swapon $part_swap; fi

if $luks_enable; then
    echo "Configurando LUKS na partição root..."
    cryptsetup luksFormat $part_root
    cryptsetup open $part_root cryptroot
    mkfs.ext4 /dev/mapper/cryptroot
    mount /dev/mapper/cryptroot /mnt
    if $home_sep; then
        echo "Configurando LUKS na partição home..."
        cryptsetup luksFormat $part_home
        cryptsetup open $part_home crypthome
        mkfs.ext4 /dev/mapper/crypthome
        mkdir -p /mnt/home
        mount /dev/mapper/crypthome /mnt/home
    fi
else
    mkfs.ext4 $part_root
    mount $part_root /mnt
    if $home_sep; then
        mkfs.ext4 $part_home
        mkdir -p /mnt/home
        mount $part_home /mnt/home
    fi
fi
mkdir -p /mnt/boot
mount $part_efi /mnt/boot

# 8. Selecionar mirrors (opcional: editar manualmente)
echo "Atualizando lista de mirrors com reflector..."
reflector --country Brazil --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# 9. Instalar sistema base
pacstrap -K /mnt base linux linux-firmware vim networkmanager

# 10. Gerar fstab
genfstab -U /mnt >> /mnt/etc/fstab

# 11. Chroot no novo sistema
echo "Entrando no novo sistema (chroot)..."

# Prompt para criação de usuário
read -p "Deseja criar um usuário comum agora? (S/n): " criar_user
if [[ $criar_user != "n" && $criar_user != "N" ]]; then
    read -p "Nome de usuário: " nome_user
    while [[ -z "$nome_user" ]]; do
        echo "O nome de usuário não pode ser vazio."
        read -p "Nome de usuário: " nome_user
    done
    read -s -p "Senha para $nome_user: " senha_user
    echo
    read -s -p "Confirme a senha: " senha_user2
    echo
    while [[ "$senha_user" != "$senha_user2" ]]; do
        echo "As senhas não coincidem. Tente novamente."
        read -s -p "Senha para $nome_user: " senha_user
        echo
        read -s -p "Confirme a senha: " senha_user2
        echo
    done
    read -p "Adicionar $nome_user ao grupo de superusuários (sudo/wheel)? (S/n): " add_wheel
    if [[ $add_wheel != "n" && $add_wheel != "N" ]]; then
        grupo_wheel=true
    else
        grupo_wheel=false
    fi
    # Salvar variáveis para uso no chroot
    echo "$nome_user" > /tmp/arch_user_nome
    echo "$senha_user" > /tmp/arch_user_senha
    echo "$grupo_wheel" > /tmp/arch_user_wheel
fi

arch-chroot /mnt /bin/bash <<EOF

# 12. Configurar timezone
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
hwclock --systohc

# 13. Localização
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# 14. Teclado persistente (opcional)
echo "KEYMAP=br-abnt2" > /etc/vconsole.conf

# 15. Hostname
echo "archlinux" > /etc/hostname

# 16. Hosts
cat <<EOT > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   archlinux.localdomain archlinux
EOT

# 17. Rede
systemctl enable NetworkManager

# 18. Senha root
passwd

# 19. Bootloader (systemd-boot para UEFI, grub para BIOS)
if [ -d /sys/firmware/efi ]; then
    bootctl install
else
    pacman -S --noconfirm grub
    grub-install --target=i386-pc /dev/$(basename $(lsblk -no pkname $part_root))
    grub-mkconfig -o /boot/grub/grub.cfg
fi

# Criação de usuário (se solicitado)
if [ -f /tmp/arch_user_nome ]; then
    nome_user=$(cat /tmp/arch_user_nome)
    senha_user=$(cat /tmp/arch_user_senha)
    grupo_wheel=$(cat /tmp/arch_user_wheel)
    useradd -m -s /bin/bash "${nome_user}"
    echo "${nome_user}:${senha_user}" | chpasswd
    if [ "${grupo_wheel}" = "true" ]; then
        usermod -aG wheel "${nome_user}"
        sed -i '/^# %wheel ALL=(ALL:ALL) ALL/s/^# //' /etc/sudoers
    fi
    rm -f /tmp/arch_user_nome /tmp/arch_user_senha /tmp/arch_user_wheel
fi

# Configurar pacman para até 10 downloads simultâneos
sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 10/' /etc/pacman.conf

EOF

echo "Instalação básica concluída!"
echo "Desmonte as partições e reinicie. Lembre-se de remover o meio de instalação."

echo "\nDeseja executar a etapa de pós-instalação com melhorias e utilitários? (s/N)"
read postinstall
if [[ $postinstall != "s" && $postinstall != "S" ]]; then
    exit 0
fi

# Função para seleção múltipla com fzf
fzf_multi_select() {
    local prompt="$1"
    shift
    local options=("$@")
    printf "%s\n" "${options[@]}" | fzf --multi --prompt="$prompt " --header="Use TAB para selecionar, ENTER para confirmar" --height=20%
}

# Detectar usuário criado para uso no pós-instalação
if [ -f /tmp/arch_user_nome ]; then
    post_user=$(cat /tmp/arch_user_nome)
    rm -f /tmp/arch_user_nome /tmp/arch_user_senha /tmp/arch_user_wheel
else
    post_user=""
fi

# Menu de pós-instalação
while true; do
    echo "\nSelecione uma categoria de pós-instalação (ou pressione ENTER para finalizar):"
    post_opts=(
        "Instalar helper AUR (yay ou paru)"
        "Sistema: SSD, drivers, firewall, rede, áudio/vídeo, multilib"
        "Escolher shell"
        "Download de fontes"
        "Browsers"
        "Produtividade"
        "Terminais (inclui ghostty)"
        "Drivers (inclui proprietários)"
        "Gerenciadores de arquivos (inclui pcmanfm)"
        "Ambiente gráfico (DE/WM)"
        "Configurar Plymouth (splash de boot)"
        "Instalar cursor Bibata Ice"
        "Instalar programas: Jogos"
        "Instalar programas: Multimídia"
        "Instalar programas: Utilitários"
        "Finalizar"
    )
    post_sel=$(printf "%s\n" "${post_opts[@]}" | fzf --prompt="Categoria: " --height=20%)
    case "$post_sel" in
        "Instalar helper AUR (yay ou paru)")
            if [ -z "$post_user" ]; then
                echo "Nenhum usuário comum foi criado. Pule esta etapa ou crie um usuário manualmente."
                continue
            fi
            echo "Qual helper AUR deseja instalar? (yay/paru) [yay]: "
            read aur_helper
            aur_helper=${aur_helper:-yay}
            arch-chroot /mnt /bin/bash <<EOF
            pacman -Sy --noconfirm git base-devel
            su - $post_user -c "git clone https://aur.archlinux.org/$aur_helper.git && cd $aur_helper && makepkg -si --noconfirm"
EOF
            ;;
        "Sistema: SSD, drivers, firewall, rede, áudio/vídeo, multilib")
            sistema_opts=(
                "Otimizações para SSD (TRIM, relatime, etc)"
                "Drivers: nvidia"
                "Drivers: amd"
                "Drivers: intel"
                "Firewall: gufw"
                "Firewall: firewalld"
                "Configuração de rede: networkmanager"
                "Configuração de rede: wpa_supplicant"
                "Configuração de DNS"
                "Áudio: pipewire"
                "Áudio: pulseaudio"
                "Vídeo: mesa"
                "Vídeo: vdpau"
                "Habilitar multilib"
            )
            sistema_sel=$(fzf_multi_select "Sistema:" "${sistema_opts[@]}")
            for opt in $sistema_sel; do
                case "$opt" in
                    "Otimizações para SSD (TRIM, relatime, etc)")
                        echo "Aplicando otimizações para SSD..."
                        arch-chroot /mnt /bin/bash <<'EOF'
# Habilitar TRIM automático
systemctl enable fstrim.timer
systemctl start fstrim.timer
# Configurar escalonador de I/O para SSD
cat <<RULE > /etc/udev/rules.d/60-ioschedulers.rules
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
RULE
# Ajustar opções de montagem para SSD: usar apenas noatime
sed -i 's/\<relatime\>//g; s/\<atime\>//g; s/\s\+/,/g; s/,,/,/g; s/,\+/,/g; s/,\+\//\//g; s/\([[:space:]]\)\+\//\//g' /etc/fstab
sed -i 's/\(defaults\|rw\)\([, ]*\)/\1,noatime\2/' /etc/fstab
EOF
                        ;;
                    "Drivers: nvidia") arch-chroot /mnt pacman -Sy --noconfirm nvidia nvidia-utils ;; 
                    "Drivers: amd") arch-chroot /mnt pacman -Sy --noconfirm xf86-video-amdgpu ;; 
                    "Drivers: intel") arch-chroot /mnt pacman -Sy --noconfirm xf86-video-intel ;; 
                    "Firewall: gufw") arch-chroot /mnt pacman -Sy --noconfirm gufw ;; 
                    "Firewall: firewalld") arch-chroot /mnt pacman -Sy --noconfirm firewalld ;; 
                    "Configuração de rede: networkmanager") arch-chroot /mnt pacman -Sy --noconfirm networkmanager; arch-chroot /mnt systemctl enable NetworkManager ;; 
                    "Configuração de rede: wpa_supplicant") arch-chroot /mnt pacman -Sy --noconfirm wpa_supplicant ;; 
                    "Configuração de DNS")
                        echo "Escolha o servidor de DNS:"
                        dns_opts=("Quad9 (9.9.9.9)" "Cloudflare (1.1.1.1)" "Padrão (do provedor)")
                        dns_sel=$(printf "%s\n" "${dns_opts[@]}" | fzf --prompt="DNS: " --height=10%)
                        case "$dns_sel" in
                            "Quad9 (9.9.9.9)")
                                arch-chroot /mnt /bin/bash -c 'echo -e "nameserver 9.9.9.9\nnameserver 149.112.112.112" > /etc/resolv.conf'
                                ;;
                            "Cloudflare (1.1.1.1)")
                                arch-chroot /mnt /bin/bash -c 'echo -e "nameserver 1.1.1.1\nnameserver 1.0.0.1" > /etc/resolv.conf'
                                ;;
                            "Padrão (do provedor)")
                                arch-chroot /mnt /bin/bash -c 'rm -f /etc/resolv.conf; systemd-resolve --status >/dev/null 2>&1 || true'
                                ;;
                        esac
                        ;;
                    "Áudio: pipewire") arch-chroot /mnt pacman -Sy --noconfirm pipewire pipewire-alsa pipewire-pulse pipewire-jack ;; 
                    "Áudio: pulseaudio") arch-chroot /mnt pacman -Sy --noconfirm pulseaudio pulseaudio-alsa ;; 
                    "Vídeo: mesa") arch-chroot /mnt pacman -Sy --noconfirm mesa mesa-utils ;; 
                    "Vídeo: vdpau") arch-chroot /mnt pacman -Sy --noconfirm libvdpau ;; 
                    "Habilitar multilib")
                        echo "Habilitando multilib..."
                        arch-chroot /mnt /bin/bash <<EOF
                        sed -i '/\\[multilib\\]/,/Include/ s/^#//' /etc/pacman.conf
                        pacman -Sy
EOF
                        ;;
                esac
            done
            ;;
        "Escolher shell")
            if [ -z "$post_user" ]; then
                echo "Nenhum usuário comum foi criado. Pule esta etapa ou crie um usuário manualmente."
                continue
            fi
            shells=("bash" "zsh" "fish" "dash" "nushell" "xonsh")
            shell_sel=$(fzf_multi_select "Shells:" "${shells[@]}")
            for pkg in $shell_sel; do
                echo "Instalando $pkg..."
                arch-chroot /mnt pacman -Sy --noconfirm $pkg
                arch-chroot /mnt chsh -s /bin/$pkg $post_user
            done
            ;;
        "Download de fontes")
            if [ -z "$post_user" ]; then
                echo "Nenhum usuário comum foi criado. Pule esta etapa ou crie um usuário manualmente."
                continue
            fi
            fontes=("ttf-ubuntu-font-family" "ttf-fira-code" "ttf-jetbrains-mono" "noto-fonts" "noto-fonts-cjk" "noto-fonts-emoji" "ttf-dejavu" "ttf-droid" "ttf-liberation" "nerd-fonts" "ttf-opensans" "ttf-font-awesome" "adobe-source-han-sans-otc-fonts")
            fontes_sel=$(fzf_multi_select "Fontes:" "${fontes[@]}")
            for pkg in $fontes_sel; do
                echo "Instalando $pkg..."
                arch-chroot /mnt pacman -Sy --noconfirm $pkg
            done
            ;;
        "Browsers")
            if [ -z "$post_user" ]; then
                echo "Nenhum usuário comum foi criado. Pule esta etapa ou crie um usuário manualmente."
                continue
            fi
            browsers=("firefox" "brave-bin" "vivaldi" "chromium" "librewolf" "google-chrome" "midori" "falkon")
            browsers_sel=$(fzf_multi_select "Browsers:" "${browsers[@]}")
            for pkg in $browsers_sel; do
                echo "Instalando $pkg..."
                arch-chroot /mnt /bin/bash <<EOF
                su -l $post_user -c "$aur_helper -S --noconfirm $pkg"
EOF
            done
            ;;
        "Produtividade")
            if [ -z "$post_user" ]; then
                echo "Nenhum usuário comum foi criado. Pule esta etapa ou crie um usuário manualmente."
                continue
            fi
            produtividade=("libreoffice-fresh" "onlyoffice-bin" "thunderbird" "evolution" "notion-app" "obsidian" "zotero" "wps-office" "okular" "evince" "gscan2pdf")
            prod_sel=$(fzf_multi_select "Produtividade:" "${produtividade[@]}")
            for pkg in $prod_sel; do
                echo "Instalando $pkg..."
                arch-chroot /mnt /bin/bash <<EOF
                su -l $post_user -c "$aur_helper -S --noconfirm $pkg"
EOF
            done
            ;;
        "Terminais (inclui ghostty)")
            if [ -z "$post_user" ]; then
                echo "Nenhum usuário comum foi criado. Pule esta etapa ou crie um usuário manualmente."
                continue
            fi
            terminais=("kitty" "alacritty" "tilix" "terminator" "gnome-terminal" "konsole" "xterm" "ghostty-bin")
            term_sel=$(fzf_multi_select "Terminais:" "${terminais[@]}")
            for pkg in $term_sel; do
                echo "Instalando $pkg..."
                arch-chroot /mnt /bin/bash <<EOF
                su -l $post_user -c "$aur_helper -S --noconfirm $pkg"
EOF
            done
            ;;
        "Drivers (inclui proprietários)")
            if [ -z "$post_user" ]; then
                echo "Nenhum usuário comum foi criado. Pule esta etapa ou crie um usuário manualmente."
                continue
            fi
            drivers=("nvidia" "nvidia-utils" "nvidia-dkms" "xf86-video-amdgpu" "xf86-video-intel" "broadcom-wl" "rtl8821ce-dkms-git" "xf86-input-synaptics" "xf86-input-libinput")
            drv_sel=$(fzf_multi_select "Drivers:" "${drivers[@]}")
            for pkg in $drv_sel; do
                echo "Instalando $pkg..."
                arch-chroot /mnt pacman -Sy --noconfirm $pkg
            done
            ;;
        "Gerenciadores de arquivos (inclui pcmanfm)")
            if [ -z "$post_user" ]; then
                echo "Nenhum usuário comum foi criado. Pule esta etapa ou crie um usuário manualmente."
                continue
            fi
            files=("thunar" "dolphin" "nautilus" "pcmanfm" "nemo" "caja" "krusader" "doublecmd-gtk" "ranger" "lf")
            files_sel=$(fzf_multi_select "Gerenciadores de arquivos:" "${files[@]}")
            for pkg in $files_sel; do
                echo "Instalando $pkg..."
                arch-chroot /mnt pacman -Sy --noconfirm $pkg
            done
            ;;
        "Ambiente gráfico (DE/WM)")
            if [ -z "$post_user" ]; then
                echo "Nenhum usuário comum foi criado. Pule esta etapa ou crie um usuário manualmente."
                continue
            fi
            desktops=("KDE Plasma" "GNOME" "XFCE" "Hyprland" "DWM")
            de_sel=$(fzf_multi_select "Ambientes gráficos:" "${desktops[@]}")
            for de in $de_sel; do
                case "$de" in
                    "KDE Plasma")
                        echo "Instalando KDE Plasma..."
                        arch-chroot /mnt pacman -Sy --noconfirm plasma kde-applications sddm
                        arch-chroot /mnt systemctl enable sddm
                        ;;
                    "GNOME")
                        echo "Instalando GNOME..."
                        arch-chroot /mnt pacman -Sy --noconfirm gnome gnome-extra gdm
                        arch-chroot /mnt systemctl enable gdm
                        ;;
                    "XFCE")
                        echo "Instalando XFCE..."
                        arch-chroot /mnt pacman -Sy --noconfirm xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
                        arch-chroot /mnt systemctl enable lightdm
                        ;;
                    "Hyprland")
                        echo "Instalando Hyprland..."
                        arch-chroot /mnt pacman -Sy --noconfirm hyprland xdg-desktop-portal-hyprland waybar foot
                        ;;
                    "DWM")
                        echo "Instalando DWM customizado..."
                        if [ -d "./dwm" ]; then
                            cp -r ./dwm /mnt/home/$post_user/
                            arch-chroot /mnt /bin/bash <<EOF
                            chown -R $post_user:$post_user /home/$post_user/dwm
                            su - $post_user -c "cd ~/dwm && make clean install"
EOF
                        else
                            echo "Pasta ./dwm não encontrada, instalando DWM via AUR helper..."
                            arch-chroot /mnt /bin/bash <<EOF
                            su -l $post_user -c "$aur_helper -S --noconfirm dwm dmenu st"
EOF
                        fi
                        ;;
                esac
            done
            ;;
        "Instalar cursor Bibata Ice")
            if [ -z "$post_user" ]; then
                echo "Nenhum usuário comum foi criado. Pule esta etapa ou crie um usuário manualmente."
                continue
            fi
            echo "Instalando e configurando o cursor Bibata Ice..."
            arch-chroot /mnt /bin/bash <<EOF
            su -l $post_user -c "$aur_helper -S --noconfirm bibata-cursor-theme-bin"
            mkdir -p /home/$post_user/.icons
            echo '[Icon Theme]' > /home/$post_user/.icons/default/index.theme
            echo 'Inherits=Bibata-Ice' >> /home/$post_user/.icons/default/index.theme
            chown -R $post_user:$post_user /home/$post_user/.icons
EOF
            # Opcional: definir para o sistema todo
            arch-chroot /mnt /bin/bash <<EOF
            mkdir -p /usr/share/icons/default
            echo '[Icon Theme]' > /usr/share/icons/default/index.theme
            echo 'Inherits=Bibata-Ice' >> /usr/share/icons/default/index.theme
EOF
            echo "Cursor Bibata Ice instalado e configurado!"
            ;;
        "Instalar programas: Jogos")
            if [ -z "$post_user" ]; then
                echo "Nenhum usuário comum foi criado. Pule esta etapa ou crie um usuário manualmente."
                continue
            fi
            jogos=("steam" "wine" "lutris" "bottles" "heroic-games-launcher" "gamemode" "protonup-qt")
            jogos_sel=$(fzf_multi_select "Jogos:" "${jogos[@]}")
            for pkg in $jogos_sel; do
                echo "Instalando $pkg..."
                arch-chroot /mnt /bin/bash <<EOF
                su -l $post_user -c "$aur_helper -S --noconfirm $pkg"
EOF
            done
            ;;
        "Instalar programas: Multimídia")
            if [ -z "$post_user" ]; then
                echo "Nenhum usuário comum foi criado. Pule esta etapa ou crie um usuário manualmente."
                continue
            fi
            multimidia=("vlc" "spotify" "mpv" "stremio" "gimp" "kdenlive" "obs-studio" "audacity")
            multimidia_sel=$(fzf_multi_select "Multimídia:" "${multimidia[@]}")
            for pkg in $multimidia_sel; do
                echo "Instalando $pkg..."
                arch-chroot /mnt /bin/bash <<EOF
                su -l $post_user -c "$aur_helper -S --noconfirm $pkg"
EOF
            done
            ;;
        "Instalar programas: Utilitários")
            if [ -z "$post_user" ]; then
                echo "Nenhum usuário comum foi criado. Pule esta etapa ou crie um usuário manualmente."
                continue
            fi
            utilitarios=("neofetch" "htop" "btop" "gparted" "filezilla" "qbittorrent" "flameshot" "timeshift" "virtualbox" "docker")
            util_sel=$(fzf_multi_select "Utilitários:" "${utilitarios[@]}")
            for pkg in $util_sel; do
                echo "Instalando $pkg..."
                arch-chroot /mnt /bin/bash <<EOF
                su -l $post_user -c "$aur_helper -S --noconfirm $pkg"
EOF
            done
            ;;
        "Configurar Plymouth (splash de boot)")
            echo "Instalando e configurando Plymouth..."
            arch-chroot /mnt pacman -Sy --noconfirm plymouth plymouth-theme-spinner
            # Adicionar hook plymouth ao mkinitcpio.conf
            arch-chroot /mnt /bin/bash <<'EOF'
            sed -i 's/^HOOKS=.*/HOOKS="base udev autodetect modconf block plymouth filesystems keyboard fsck"/' /etc/mkinitcpio.conf
            mkinitcpio -P
EOF
            # Configurar splash no kernel para systemd-boot e GRUB
            arch-chroot /mnt /bin/bash <<'EOF'
            # Para systemd-boot
            if [ -d /boot/loader/entries ]; then
              for entry in /boot/loader/entries/*.conf; do
                sed -i 's/\(options .*$\)/\1 splash/' "$entry"
              done
            fi
            # Para GRUB
            if grep -q GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub; then
              sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash /' /etc/default/grub
              grub-mkconfig -o /boot/grub/grub.cfg
            fi
EOF
            # Ativar tema padrão
            arch-chroot /mnt plymouth-set-default-theme -R spinner
            echo "Plymouth instalado e configurado! O splash aparecerá no próximo boot."
            ;;
        "Finalizar"|"")
            echo "Pós-instalação finalizada."
            break
            ;;
        *)
            echo "Opção inválida."
            ;;
    esac
done

# Após montar root em /mnt, antes do chroot
if $swap_enable && [[ $swap_type == "f" ]]; then
    echo "Criando swapfile de ${swap_size}MiB..."
    arch-chroot /mnt /bin/bash <<EOF
    fallocate -l ${swap_size}M /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap defaults 0 0' >> /etc/fstab
EOF
fi 