#!/bin/bash
# Script de instalação básica do Arch Linux
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

echo "Instalação básica concluída!"
echo "Desmonte as partições e reinicie. Lembre-se de remover o meio de instalação."
echo ""
echo "Após o reinício, execute o script de pós-instalação:"
echo "sudo ./arch_post_install.sh" 