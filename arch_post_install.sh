#!/bin/bash
# Script de pós-instalação do Arch Linux
# Execute após o reinício do sistema, como usuário com privilégios sudo

set -e

# Verificar se fzf está instalado, se não instalar
if ! command -v fzf &> /dev/null; then
    echo "fzf não encontrado. Instalando..."
    sudo pacman -Sy --noconfirm fzf
fi

# Verificar se o usuário tem privilégios sudo
if ! sudo -n true 2>/dev/null; then
    echo "Este script requer privilégios sudo."
    echo "Execute: sudo ./arch_post_install.sh"
    exit 1
fi

# Função para seleção múltipla com fzf
fzf_multi_select() {
    local prompt="$1"
    shift
    local options=("$@")
    printf "%s\n" "${options[@]}" | fzf --multi --prompt="$prompt " --header="Use TAB para selecionar, ENTER para confirmar" --height=20%
}

# Detectar usuário atual
current_user=$(whoami)
echo "Usuário atual: $current_user"

# Menu de pós-instalação
while true; do
    echo "\nSelecione uma categoria de pós-instalação (ou pressione ENTER para finalizar):"
    post_opts=(
        "Instalar helper AUR (yay ou paru)"
        "Sistema: SSD, drivers, firewall, rede, áudio/vídeo, multilib"
        "Melhorias para Máquinas Virtuais"
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
            echo "Qual helper AUR deseja instalar? (yay/paru) [yay]: "
            read aur_helper
            aur_helper=${aur_helper:-yay}
            
            # Verificar se já está instalado
            if command -v $aur_helper &> /dev/null; then
                echo "$aur_helper já está instalado!"
                continue
            fi
            
            echo "Instalando $aur_helper..."
            sudo pacman -Sy --noconfirm git base-devel
            git clone https://aur.archlinux.org/$aur_helper.git
            cd $aur_helper
            makepkg -si --noconfirm
            cd ..
            rm -rf $aur_helper
            
            # Verificar se a instalação foi bem-sucedida
            if command -v $aur_helper &> /dev/null; then
                echo "$aur_helper instalado com sucesso!"
            else
                echo "Erro na instalação do $aur_helper. Tente novamente."
            fi
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
                        sudo systemctl enable fstrim.timer
                        sudo systemctl start fstrim.timer
                        # Configurar escalonador de I/O para SSD
                        sudo tee /etc/udev/rules.d/60-ioschedulers.rules > /dev/null <<'EOF'
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
EOF
                        # Ajustar opções de montagem para SSD: usar apenas noatime
                        sudo sed -i 's/\<relatime\>//g; s/\<atime\>//g; s/\s\+/,/g; s/,,/,/g; s/,\+/,/g; s/,\+\//\//g; s/\([[:space:]]\)\+\//\//g' /etc/fstab
                        sudo sed -i 's/\(defaults\|rw\)\([, ]*\)/\1,noatime\2/' /etc/fstab
                        ;;
                    "Drivers: nvidia") sudo pacman -Sy --noconfirm nvidia nvidia-utils ;; 
                    "Drivers: amd") sudo pacman -Sy --noconfirm xf86-video-amdgpu ;; 
                    "Drivers: intel") sudo pacman -Sy --noconfirm xf86-video-intel ;; 
                    "Firewall: gufw") sudo pacman -Sy --noconfirm gufw ;; 
                    "Firewall: firewalld") sudo pacman -Sy --noconfirm firewalld ;; 
                    "Configuração de rede: networkmanager") sudo pacman -Sy --noconfirm networkmanager; sudo systemctl enable NetworkManager ;; 
                    "Configuração de rede: wpa_supplicant") sudo pacman -Sy --noconfirm wpa_supplicant ;; 
                    "Configuração de DNS")
                        echo "Escolha o servidor de DNS:"
                        dns_opts=("Quad9 (9.9.9.9)" "Cloudflare (1.1.1.1)" "Padrão (do provedor)")
                        dns_sel=$(printf "%s\n" "${dns_opts[@]}" | fzf --prompt="DNS: " --height=10%)
                        case "$dns_sel" in
                            "Quad9 (9.9.9.9)")
                                sudo tee /etc/resolv.conf > /dev/null <<EOF
nameserver 9.9.9.9
nameserver 149.112.112.112
EOF
                                ;;
                            "Cloudflare (1.1.1.1)")
                                sudo tee /etc/resolv.conf > /dev/null <<EOF
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF
                                ;;
                            "Padrão (do provedor)")
                                sudo rm -f /etc/resolv.conf
                                sudo systemd-resolve --status >/dev/null 2>&1 || true
                                ;;
                        esac
                        ;;
                    "Áudio: pipewire") sudo pacman -Sy --noconfirm pipewire pipewire-alsa pipewire-pulse pipewire-jack ;; 
                    "Áudio: pulseaudio") sudo pacman -Sy --noconfirm pulseaudio pulseaudio-alsa ;; 
                    "Vídeo: mesa") sudo pacman -Sy --noconfirm mesa mesa-utils ;; 
                    "Vídeo: vdpau") sudo pacman -Sy --noconfirm libvdpau ;; 
                    "Habilitar multilib")
                        echo "Habilitando multilib..."
                        sudo sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
                        sudo pacman -Sy
                        ;;
                esac
            done
            ;;
        "Melhorias para Máquinas Virtuais")
            echo "Detectando ambiente de máquina virtual..."
            
            # Detectar tipo de VM
            vm_type=""
            if grep -q "VMware" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
                vm_type="vmware"
                echo "Detectado: VMware"
            elif grep -q "VirtualBox" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
                vm_type="virtualbox"
                echo "Detectado: VirtualBox"
            elif grep -q "QEMU" /sys/class/dmi/id/sys_vendor 2>/dev/null || grep -q "QEMU" /proc/cpuinfo 2>/dev/null; then
                vm_type="qemu"
                echo "Detectado: QEMU/KVM"
            elif grep -q "Microsoft" /sys/class/dmi/id/sys_vendor 2>/dev/null && grep -q "Virtual" /sys/class/dmi/id/product_name 2>/dev/null; then
                vm_type="hyperv"
                echo "Detectado: Hyper-V"
            elif grep -q "Xen" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
                vm_type="xen"
                echo "Detectado: Xen"
            else
                echo "Nenhuma VM detectada ou ambiente desconhecido."
                read -p "Deseja continuar mesmo assim? (s/N): " continue_vm
                if [[ $continue_vm != "s" && $continue_vm != "S" ]]; then
                    continue
                fi
                vm_type="generic"
            fi
            
            vm_opts=(
                "Drivers de vídeo para VM"
                "Ferramentas de VM (guest tools)"
                "Otimizações de performance"
                "Melhorias de rede"
                "Configurações de display"
                "Todas as melhorias"
            )
            vm_sel=$(fzf_multi_select "Melhorias para VM:" "${vm_opts[@]}")
            
            for opt in $vm_sel; do
                case "$opt" in
                    "Drivers de vídeo para VM")
                        echo "Instalando drivers de vídeo para VM..."
                        case "$vm_type" in
                            "vmware")
                                sudo pacman -Sy --noconfirm xf86-video-vmware
                                ;;
                            "virtualbox")
                                sudo pacman -Sy --noconfirm virtualbox-guest-utils
                                ;;
                            "qemu")
                                sudo pacman -Sy --noconfirm xf86-video-qxl spice-vdagent
                                ;;
                            "hyperv")
                                sudo pacman -Sy --noconfirm xf86-video-fbdev
                                ;;
                            *)
                                sudo pacman -Sy --noconfirm xf86-video-fbdev xf86-video-vesa
                                ;;
                        esac
                        ;;
                    "Ferramentas de VM (guest tools)")
                        echo "Instalando ferramentas de VM..."
                        case "$vm_type" in
                            "vmware")
                                # Verificar se AUR helper está disponível para VMware tools
                                if command -v yay &> /dev/null || command -v paru &> /dev/null; then
                                    aur_helper=""
                                    if command -v yay &> /dev/null; then
                                        aur_helper="yay"
                                    elif command -v paru &> /dev/null; then
                                        aur_helper="paru"
                                    fi
                                    $aur_helper -S --noconfirm open-vm-tools
                                else
                                    sudo pacman -Sy --noconfirm open-vm-tools
                                fi
                                sudo systemctl enable vmtoolsd
                                sudo systemctl start vmtoolsd
                                ;;
                            "virtualbox")
                                sudo pacman -Sy --noconfirm virtualbox-guest-utils
                                sudo systemctl enable vboxservice
                                sudo systemctl start vboxservice
                                ;;
                            "qemu")
                                sudo pacman -Sy --noconfirm spice-vdagent qemu-guest-agent
                                sudo systemctl enable spice-vdagentd
                                sudo systemctl start spice-vdagentd
                                sudo systemctl enable qemu-guest-agent
                                sudo systemctl start qemu-guest-agent
                                ;;
                            "hyperv")
                                sudo pacman -Sy --noconfirm hyperv
                                sudo systemctl enable hv_fcopy_daemon
                                sudo systemctl start hv_fcopy_daemon
                                sudo systemctl enable hv_kvp_daemon
                                sudo systemctl start hv_kvp_daemon
                                sudo systemctl enable hv_vss_daemon
                                sudo systemctl start hv_vss_daemon
                                ;;
                        esac
                        ;;
                    "Otimizações de performance")
                        echo "Aplicando otimizações de performance para VM..."
                        
                        # Configurar escalonador de I/O para VM
                        sudo tee /etc/udev/rules.d/60-ioschedulers-vm.rules > /dev/null <<'EOF'
# Configurações de I/O para VMs
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
EOF
                        
                        # Otimizações de memória
                        sudo tee -a /etc/sysctl.conf > /dev/null <<'EOF'

# Otimizações para VMs
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
EOF
                        
                        # Configurar CPU governor para performance
                        sudo pacman -Sy --noconfirm cpupower
                        sudo cpupower frequency-set -g performance
                        
                        # Habilitar serviço cpupower
                        sudo systemctl enable cpupower
                        ;;
                    "Melhorias de rede")
                        echo "Configurando melhorias de rede para VM..."
                        
                        # Otimizações de rede
                        sudo tee -a /etc/sysctl.conf > /dev/null <<'EOF'

# Otimizações de rede para VMs
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_congestion_control=bbr
EOF
                        
                        # Configurar DNS otimizado
                        sudo tee /etc/resolv.conf > /dev/null <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
                        ;;
                    "Configurações de display")
                        echo "Configurando display para VM..."
                        
                        # Configurar X11 para melhor performance em VM
                        sudo tee /etc/X11/xorg.conf.d/10-vm.conf > /dev/null <<'EOF'
Section "Device"
    Identifier "VM Graphics"
    Driver "fbdev"
    Option "AccelMethod" "none"
EndSection

Section "Screen"
    Identifier "Default Screen"
    Device "VM Graphics"
    DefaultDepth 24
EndSection
EOF
                        
                        # Configurar compositor para melhor performance
                        if [ -f ~/.config/picom/picom.conf ]; then
                            # Backup da configuração atual
                            cp ~/.config/picom/picom.conf ~/.config/picom/picom.conf.backup
                            
                            # Adicionar otimizações para VM
                            cat >> ~/.config/picom/picom.conf <<'EOF'

# Otimizações para VM
backend = "xrender"
vsync = false
unredir-if-possible = true
EOF
                        fi
                        ;;
                    "Todas as melhorias")
                        echo "Aplicando todas as melhorias para VM..."
                        # Executar todas as opções acima
                        for improvement in "Drivers de vídeo para VM" "Ferramentas de VM (guest tools)" "Otimizações de performance" "Melhorias de rede" "Configurações de display"; do
                            echo "Aplicando: $improvement"
                            case "$improvement" in
                                "Drivers de vídeo para VM")
                                    case "$vm_type" in
                                        "vmware") sudo pacman -Sy --noconfirm xf86-video-vmware ;;
                                        "virtualbox") sudo pacman -Sy --noconfirm virtualbox-guest-utils ;;
                                        "qemu") sudo pacman -Sy --noconfirm xf86-video-qxl spice-vdagent ;;
                                        "hyperv") sudo pacman -Sy --noconfirm xf86-video-fbdev ;;
                                        *) sudo pacman -Sy --noconfirm xf86-video-fbdev xf86-video-vesa ;;
                                    esac
                                    ;;
                                "Ferramentas de VM (guest tools)")
                                    case "$vm_type" in
                                        "vmware")
                                            if command -v yay &> /dev/null || command -v paru &> /dev/null; then
                                                aur_helper=""
                                                if command -v yay &> /dev/null; then aur_helper="yay"; elif command -v paru &> /dev/null; then aur_helper="paru"; fi
                                                $aur_helper -S --noconfirm open-vm-tools
                                            else
                                                sudo pacman -Sy --noconfirm open-vm-tools
                                            fi
                                            sudo systemctl enable vmtoolsd && sudo systemctl start vmtoolsd
                                            ;;
                                        "virtualbox")
                                            sudo pacman -Sy --noconfirm virtualbox-guest-utils
                                            sudo systemctl enable vboxservice && sudo systemctl start vboxservice
                                            ;;
                                        "qemu")
                                            sudo pacman -Sy --noconfirm spice-vdagent qemu-guest-agent
                                            sudo systemctl enable spice-vdagentd && sudo systemctl start spice-vdagentd
                                            sudo systemctl enable qemu-guest-agent && sudo systemctl start qemu-guest-agent
                                            ;;
                                        "hyperv")
                                            sudo pacman -Sy --noconfirm hyperv
                                            sudo systemctl enable hv_fcopy_daemon && sudo systemctl start hv_fcopy_daemon
                                            sudo systemctl enable hv_kvp_daemon && sudo systemctl start hv_kvp_daemon
                                            sudo systemctl enable hv_vss_daemon && sudo systemctl start hv_vss_daemon
                                            ;;
                                    esac
                                    ;;
                                "Otimizações de performance")
                                    sudo tee /etc/udev/rules.d/60-ioschedulers-vm.rules > /dev/null <<'EOF'
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
EOF
                                    sudo tee -a /etc/sysctl.conf > /dev/null <<'EOF'

# Otimizações para VMs
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
EOF
                                    sudo pacman -Sy --noconfirm cpupower
                                    sudo cpupower frequency-set -g performance
                                    sudo systemctl enable cpupower
                                    ;;
                                "Melhorias de rede")
                                    sudo tee -a /etc/sysctl.conf > /dev/null <<'EOF'

# Otimizações de rede para VMs
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_congestion_control=bbr
EOF
                                    sudo tee /etc/resolv.conf > /dev/null <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
                                    ;;
                                "Configurações de display")
                                    sudo tee /etc/X11/xorg.conf.d/10-vm.conf > /dev/null <<'EOF'
Section "Device"
    Identifier "VM Graphics"
    Driver "fbdev"
    Option "AccelMethod" "none"
EndSection

Section "Screen"
    Identifier "Default Screen"
    Device "VM Graphics"
    DefaultDepth 24
EndSection
EOF
                                    ;;
                            esac
                        done
                        ;;
                esac
            done
            
            echo "Melhorias para VM aplicadas com sucesso!"
            echo "Reinicie o sistema para aplicar todas as configurações."
            ;;
        "Escolher shell")
            shells=("bash" "zsh" "fish" "dash" "nushell" "xonsh")
            shell_sel=$(fzf_multi_select "Shells:" "${shells[@]}")
            for pkg in $shell_sel; do
                echo "Instalando $pkg..."
                sudo pacman -Sy --noconfirm $pkg
                chsh -s /bin/$pkg $current_user
            done
            ;;
        "Download de fontes")
            fontes=("ttf-ubuntu-font-family" "ttf-fira-code" "ttf-jetbrains-mono" "noto-fonts" "noto-fonts-cjk" "noto-fonts-emoji" "ttf-dejavu" "ttf-droid" "ttf-liberation" "nerd-fonts" "ttf-opensans" "ttf-font-awesome" "adobe-source-han-sans-otc-fonts")
            fontes_sel=$(fzf_multi_select "Fontes:" "${fontes[@]}")
            for pkg in $fontes_sel; do
                echo "Instalando $pkg..."
                sudo pacman -Sy --noconfirm $pkg
            done
            ;;
        "Browsers")
            # Verificar se AUR helper está instalado
            if ! command -v yay &> /dev/null && ! command -v paru &> /dev/null; then
                echo "Nenhum helper AUR encontrado. Instale yay ou paru primeiro."
                continue
            fi
            aur_helper=""
            if command -v yay &> /dev/null; then
                aur_helper="yay"
            elif command -v paru &> /dev/null; then
                aur_helper="paru"
            fi
            
            browsers=("firefox" "brave-bin" "vivaldi" "chromium" "librewolf" "google-chrome" "midori" "falkon")
            browsers_sel=$(fzf_multi_select "Browsers:" "${browsers[@]}")
            for pkg in $browsers_sel; do
                echo "Instalando $pkg..."
                $aur_helper -S --noconfirm $pkg
            done
            ;;
        "Produtividade")
            # Verificar se AUR helper está instalado
            if ! command -v yay &> /dev/null && ! command -v paru &> /dev/null; then
                echo "Nenhum helper AUR encontrado. Instale yay ou paru primeiro."
                continue
            fi
            aur_helper=""
            if command -v yay &> /dev/null; then
                aur_helper="yay"
            elif command -v paru &> /dev/null; then
                aur_helper="paru"
            fi
            
            produtividade=("libreoffice-fresh" "onlyoffice-bin" "thunderbird" "evolution" "notion-app" "obsidian" "zotero" "wps-office" "okular" "evince" "gscan2pdf")
            prod_sel=$(fzf_multi_select "Produtividade:" "${produtividade[@]}")
            for pkg in $prod_sel; do
                echo "Instalando $pkg..."
                $aur_helper -S --noconfirm $pkg
            done
            ;;
        "Terminais (inclui ghostty)")
            # Verificar se AUR helper está instalado
            if ! command -v yay &> /dev/null && ! command -v paru &> /dev/null; then
                echo "Nenhum helper AUR encontrado. Instale yay ou paru primeiro."
                continue
            fi
            aur_helper=""
            if command -v yay &> /dev/null; then
                aur_helper="yay"
            elif command -v paru &> /dev/null; then
                aur_helper="paru"
            fi
            
            terminais=("kitty" "alacritty" "tilix" "terminator" "gnome-terminal" "konsole" "xterm" "ghostty-bin")
            term_sel=$(fzf_multi_select "Terminais:" "${terminais[@]}")
            for pkg in $term_sel; do
                echo "Instalando $pkg..."
                $aur_helper -S --noconfirm $pkg
            done
            ;;
        "Drivers (inclui proprietários)")
            drivers=("nvidia" "nvidia-utils" "nvidia-dkms" "xf86-video-amdgpu" "xf86-video-intel" "broadcom-wl" "rtl8821ce-dkms-git" "xf86-input-synaptics" "xf86-input-libinput")
            drv_sel=$(fzf_multi_select "Drivers:" "${drivers[@]}")
            for pkg in $drv_sel; do
                echo "Instalando $pkg..."
                sudo pacman -Sy --noconfirm $pkg
            done
            ;;
        "Gerenciadores de arquivos (inclui pcmanfm)")
            files=("thunar" "dolphin" "nautilus" "pcmanfm" "nemo" "caja" "krusader" "doublecmd-gtk" "ranger" "lf")
            files_sel=$(fzf_multi_select "Gerenciadores de arquivos:" "${files[@]}")
            for pkg in $files_sel; do
                echo "Instalando $pkg..."
                sudo pacman -Sy --noconfirm $pkg
            done
            ;;
        "Ambiente gráfico (DE/WM)")
            desktops=("KDE Plasma" "GNOME" "XFCE" "Hyprland" "DWM")
            de_sel=$(fzf_multi_select "Ambientes gráficos:" "${desktops[@]}")
            for de in $de_sel; do
                case "$de" in
                    "KDE Plasma")
                        echo "Instalando KDE Plasma..."
                        sudo pacman -Sy --noconfirm plasma kde-applications sddm
                        sudo systemctl enable sddm
                        ;;
                    "GNOME")
                        echo "Instalando GNOME..."
                        sudo pacman -Sy --noconfirm gnome gnome-extra gdm
                        sudo systemctl enable gdm
                        ;;
                    "XFCE")
                        echo "Instalando XFCE..."
                        sudo pacman -Sy --noconfirm xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
                        sudo systemctl enable lightdm
                        ;;
                    "Hyprland")
                        echo "Instalando Hyprland..."
                        sudo pacman -Sy --noconfirm hyprland xdg-desktop-portal-hyprland waybar foot
                        ;;
                    "DWM")
                        echo "Instalando DWM customizado..."
                        if [ -d "./dwm" ]; then
                            cp -r ./dwm ~/
                            cd ~/dwm
                            make clean install
                            cd -
                        else
                            echo "Pasta ./dwm não encontrada, instalando DWM via AUR helper..."
                            # Verificar se AUR helper está instalado
                            if ! command -v yay &> /dev/null && ! command -v paru &> /dev/null; then
                                echo "Nenhum helper AUR encontrado. Instale yay ou paru primeiro."
                                continue
                            fi
                            aur_helper=""
                            if command -v yay &> /dev/null; then
                                aur_helper="yay"
                            elif command -v paru &> /dev/null; then
                                aur_helper="paru"
                            fi
                            $aur_helper -S --noconfirm dwm dmenu st
                        fi
                        ;;
                esac
            done
            ;;
        "Instalar cursor Bibata Ice")
            # Verificar se AUR helper está instalado
            if ! command -v yay &> /dev/null && ! command -v paru &> /dev/null; then
                echo "Nenhum helper AUR encontrado. Instale yay ou paru primeiro."
                continue
            fi
            aur_helper=""
            if command -v yay &> /dev/null; then
                aur_helper="yay"
            elif command -v paru &> /dev/null; then
                aur_helper="paru"
            fi
            
            echo "Instalando e configurando o cursor Bibata Ice..."
            $aur_helper -S --noconfirm bibata-cursor-theme-bin
            mkdir -p ~/.icons
            echo '[Icon Theme]' > ~/.icons/default/index.theme
            echo 'Inherits=Bibata-Ice' >> ~/.icons/default/index.theme
            # Opcional: definir para o sistema todo
            sudo mkdir -p /usr/share/icons/default
            echo '[Icon Theme]' | sudo tee /usr/share/icons/default/index.theme > /dev/null
            echo 'Inherits=Bibata-Ice' | sudo tee -a /usr/share/icons/default/index.theme > /dev/null
            echo "Cursor Bibata Ice instalado e configurado!"
            ;;
        "Instalar programas: Jogos")
            # Verificar se AUR helper está instalado
            if ! command -v yay &> /dev/null && ! command -v paru &> /dev/null; then
                echo "Nenhum helper AUR encontrado. Instale yay ou paru primeiro."
                continue
            fi
            aur_helper=""
            if command -v yay &> /dev/null; then
                aur_helper="yay"
            elif command -v paru &> /dev/null; then
                aur_helper="paru"
            fi
            
            jogos=("steam" "wine" "lutris" "bottles" "heroic-games-launcher" "gamemode" "protonup-qt")
            jogos_sel=$(fzf_multi_select "Jogos:" "${jogos[@]}")
            for pkg in $jogos_sel; do
                echo "Instalando $pkg..."
                $aur_helper -S --noconfirm $pkg
            done
            ;;
        "Instalar programas: Multimídia")
            # Verificar se AUR helper está instalado
            if ! command -v yay &> /dev/null && ! command -v paru &> /dev/null; then
                echo "Nenhum helper AUR encontrado. Instale yay ou paru primeiro."
                continue
            fi
            aur_helper=""
            if command -v yay &> /dev/null; then
                aur_helper="yay"
            elif command -v paru &> /dev/null; then
                aur_helper="paru"
            fi
            
            multimidia=("vlc" "spotify" "mpv" "stremio" "gimp" "kdenlive" "obs-studio" "audacity")
            multimidia_sel=$(fzf_multi_select "Multimídia:" "${multimidia[@]}")
            for pkg in $multimidia_sel; do
                echo "Instalando $pkg..."
                $aur_helper -S --noconfirm $pkg
            done
            ;;
        "Instalar programas: Utilitários")
            # Verificar se AUR helper está instalado
            if ! command -v yay &> /dev/null && ! command -v paru &> /dev/null; then
                echo "Nenhum helper AUR encontrado. Instale yay ou paru primeiro."
                continue
            fi
            aur_helper=""
            if command -v yay &> /dev/null; then
                aur_helper="yay"
            elif command -v paru &> /dev/null; then
                aur_helper="paru"
            fi
            
            utilitarios=("neofetch" "htop" "btop" "gparted" "filezilla" "qbittorrent" "flameshot" "timeshift" "virtualbox" "docker")
            util_sel=$(fzf_multi_select "Utilitários:" "${utilitarios[@]}")
            for pkg in $util_sel; do
                echo "Instalando $pkg..."
                $aur_helper -S --noconfirm $pkg
            done
            ;;
        "Configurar Plymouth (splash de boot)")
            echo "Instalando e configurando Plymouth..."
            sudo pacman -Sy --noconfirm plymouth
            
            # Instalar tema do Plymouth (usando tema disponível no AUR)
            if command -v yay &> /dev/null || command -v paru &> /dev/null; then
                aur_helper=""
                if command -v yay &> /dev/null; then
                    aur_helper="yay"
                elif command -v paru &> /dev/null; then
                    aur_helper="paru"
                fi
                echo "Instalando tema Plymouth via AUR..."
                $aur_helper -S --noconfirm plymouth-theme-arch-charge
            else
                echo "AUR helper não encontrado. Instalando tema básico..."
                sudo pacman -Sy --noconfirm plymouth-theme-arch-charge
            fi
            
            # Adicionar hook plymouth ao mkinitcpio.conf
            sudo sed -i 's/^HOOKS=.*/HOOKS="base udev autodetect modconf block plymouth filesystems keyboard fsck"/' /etc/mkinitcpio.conf
            sudo mkinitcpio -P
            
            # Configurar splash no kernel para systemd-boot e GRUB
            # Para systemd-boot
            if [ -d /boot/loader/entries ]; then
              for entry in /boot/loader/entries/*.conf; do
                sudo sed -i 's/\(options .*$\)/\1 splash/' "$entry"
              done
            fi
            # Para GRUB
            if grep -q GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub; then
              sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash /' /etc/default/grub
              sudo grub-mkconfig -o /boot/grub/grub.cfg
            fi
            
            # Ativar tema padrão
            sudo plymouth-set-default-theme -R arch-charge
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

echo "Pós-instalação concluída!"
echo "Reinicie o sistema para aplicar todas as mudanças." 