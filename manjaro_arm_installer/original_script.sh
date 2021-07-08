#! /bin/bash

# Set globals
# *****************************
VERSION="1.4.4"
# *****************************
TMPDIR=/var/tmp/manjaro-arm-installer
ARCH='aarch64'
CARCH=$(uname -m)
NSPAWN='systemd-nspawn -q --resolv-conf=copy-host --timezone=off -D'
srv_list=/var/tmp/manjaro-arm-installer/services_list

# set colorscheme
if [[ -f "./dialogrc_gui" ]]; then
export DIALOGRC="./dialogrc_gui"
else
export DIALOGRC="/etc/manjaro-arm-installer/dialogrc_gui"
fi

# clearing variables
DEVICE=""
EDITION=""
USER=""
USERGROUPS=""
FULLNAME=""
PASSWORD=""
CONFIRMPASSWORD=""
CONFIRMROOTPASSWORD=""
ROOTPASSWORD=""
SDCARD=""
SDTYP=""
SDDEV=""
DEV_NAME=""
FSTYPE=""
TIMEZONE=""
LOCALE=""
HOSTNAME=""
CRYPT=""

# check if root
if [ "$EUID" -ne 0 ]; then
    echo "*******************************************************************************************"
    echo "*                                                                                         *"
    echo "*     This script requires root permissions to run. Please run as root or with sudo!      *"
    echo "*                                                                                         *"
    echo "*******************************************************************************************"
  exit
fi

# Sanity checks for dependencies
declare -a DEPENDENCIES=("git" "parted" "systemd-nspawn" "wget" "dialog" "bsdtar" "openssl" "awk" "btrfs" "mkfs.vfat" "mkfs.btrfs" "cryptsetup")

for i in "${DEPENDENCIES[@]}"; do
  if ! [[ -f "/bin/$i" || -f "/sbin/$i" || -f "/usr/bin/$i" || -f "/usr/sbin/$i" ]] ; then
    echo "$i command is missing! Please install the relevant package."
    exit 1
  fi
done

if [[ "$CARCH" != "aarch64" ]]; then
if [ ! -f "/usr/lib/binfmt.d/qemu-static.conf" ]; then
    echo "qemu-static.conf file is missing. Please install the relevant package."
    exit 1
fi
fi


# Functions
msg() {
    ALL_OFF="\e[1;0m"
    BOLD="\e[1;1m"
    GREEN="${BOLD}\e[1;32m"
      local mesg=$1; shift
      printf "${GREEN}==>${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
 }

info() {
    ALL_OFF="\e[1;0m"
    BOLD="\e[1;1m"
    BLUE="${BOLD}\e[1;34m"
      local mesg=$1; shift
      printf "${BLUE}  ->${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
 }

usage_build_installer() {
    echo "Usage: ${0##*/} [options]"
    echo '    -h                 This help'
    echo ''
    echo ''
    exit $1
}

get_timer(){
    echo $(date +%s)
}

# $1: start timer
elapsed_time(){
    echo $(echo $1 $(get_timer) | awk '{ printf "%0.2f",($2-$1)/60 }')
}

show_elapsed_time(){
    msg "Time %s: %s minutes..." "$1" "$(elapsed_time $2)"
}

installer_getarmprofiles () {
    info "Getting package lists ready for $DEVICE $EDITION edition..."
    rm -rf $TMPDIR/arm-profiles
    mkdir -p $TMPDIR
    chmod 777 $TMPDIR
    git clone https://gitlab.manjaro.org/manjaro-arm/applications/arm-profiles.git $TMPDIR/arm-profiles/ 1> /dev/null 2>&1

}

create_install() {
    msg "Creating install for $DEVICE..."
    info "Used device is ${SDCARD}"
    
    # fetch and extract rootfs
    info "Downloading latest $ARCH rootfs..."
    cd $TMPDIR
    if [ -f Manjaro-ARM-$ARCH-latest.tar.gz* ]; then
    rm Manjaro-ARM_$ARCH-latest.tar.gz*
    fi
    wget -q --show-progress --progress=bar:force:noscroll https://github.com/manjaro-arm/rootfs/releases/latest/download/Manjaro-ARM-$ARCH-latest.tar.gz
    
    info "Extracting $ARCH rootfs..."
    bsdtar -xpf $TMPDIR/Manjaro-ARM-$ARCH-latest.tar.gz -C $TMPDIR/root
    
    info "Setting up keyrings..."
    $NSPAWN $TMPDIR/root pacman-key --init 1> /dev/null 2>&1
    $NSPAWN $TMPDIR/root pacman-key --populate archlinux archlinuxarm manjaro manjaro-arm 1> /dev/null 2>&1
    
    info "Generating mirrorlist..."
    $NSPAWN $TMPDIR/root pacman-mirrors -f10 1> /dev/null 2>&1
    
    info "Installing packages for $EDITION on $DEVICE..."
    # Setup cache mount
    mkdir -p $TMPDIR/pkg-cache
    mount -o bind $TMPDIR/pkg-cache $TMPDIR/root/var/cache/pacman/pkg
    # Install device and editions specific packages
    $NSPAWN $TMPDIR/root pacman -Syyu base manjaro-system manjaro-release systemd systemd-libs $PKG_EDITION $PKG_DEVICE --noconfirm
    
    info "Enabling services..."
    # Enable services
    $NSPAWN $TMPDIR/root systemctl enable getty.target haveged.service 1>/dev/null

    while read service; do
        if [ -e $TMPDIR/root/usr/lib/systemd/system/$service ]; then
            echo "Enabling $service ..."
            $NSPAWN $TMPDIR/root systemctl enable $service 1>/dev/null
        else
            echo "$service not found in rootfs. Skipping."
        fi
    done < $srv_list
    if [ -f $TMPDIR/root/usr/bin/xdg-user-dirs-update ]; then
    $NSPAWN $TMPDIR/root systemctl --global enable xdg-user-dirs-update.service 1> /dev/null 2>&1
    fi

    info "Applying overlay for $EDITION..."
    cp -ap $TMPDIR/arm-profiles/overlays/$EDITION/* $TMPDIR/root/

    info "Setting up users..."
    #setup users
    echo "$USER" > $TMPDIR/user
    echo "$PASSWORD" > $TMPDIR/password
    echo "$ROOTPASSWORD" > $TMPDIR/rootpassword

    info "Setting password for root ..."
    $NSPAWN $TMPDIR/root awk -i inplace -F: "BEGIN {OFS=FS;} \$1 == \"root\" {\$2=\"$(openssl passwd -6 $(cat $TMPDIR/rootpassword))\"} 1" /etc/shadow 1> /dev/null 2>&1

    info "Adding user..."
    $NSPAWN $TMPDIR/root useradd -m -G wheel,sys,audio,input,video,storage,lp,network,users,power -p $(openssl passwd -6 $(cat $TMPDIR/password)) -s /bin/bash $(cat $TMPDIR/user) 1> /dev/null 2>&1
    $NSPAWN $TMPDIR/root usermod -aG $USERGROUPS $(cat $TMPDIR/user) 1> /dev/null 2>&1
    $NSPAWN $TMPDIR/root chfn -f "$FULLNAME" $(cat $TMPDIR/user) 1> /dev/null 2>&1
    
    info "Enabling user services..."
    if [[ "$EDITION" = "minimal" ]] || [[ "$EDITION" = "server" ]]; then
        echo "No user services for $EDITION edition"
    else
        $NSPAWN $TMPDIR/root --user $(cat $TMPDIR/user) systemctl --user enable pulseaudio.service 1> /dev/null 2>&1
    fi
    
    info "Setting up system settings..."
    #system setup
    $NSPAWN $TMPDIR/root chmod u+s /usr/bin/ping 1> /dev/null 2>&1
    rm -f $TMPDIR/root/etc/ssl/certs/ca-certificates.crt
    rm -f $TMPDIR/root/etc/ca-certificates/extracted/tls-ca-bundle.pem
    cp -a /etc/ssl/certs/ca-certificates.crt $TMPDIR/root/etc/ssl/certs/
    cp -a /etc/ca-certificates/extracted/tls-ca-bundle.pem $TMPDIR/root/etc/ca-certificates/extracted/
    $NSPAWN $TMPDIR/root ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime 1> /dev/null 2>&1
    $NSPAWN $TMPDIR/root sed -i s/"#$LOCALE"/"$LOCALE"/g /etc/locale.gen 1> /dev/null 2>&1
    echo "LANG=$LOCALE" | tee --append $TMPDIR/root/etc/locale.conf 1> /dev/null 2>&1
    $NSPAWN $TMPDIR/root locale-gen
    echo "KEYMAP=$CLIKEYMAP" | tee --append $TMPDIR/root/etc/vconsole.conf 1> /dev/null 2>&1
    if [[ "$EDITION" != "minimal" ]] && [[ "$EDITION" != "server" ]]; then
    echo 'Section "InputClass"' > $TMPDIR/root/etc/X11/xorg.conf.d/00-keyboard.conf
    echo 'Identifier "system-keyboard"' >> $TMPDIR/root/etc/X11/xorg.conf.d/00-keyboard.conf
    echo 'Option "XkbLayout" "us"' >> $TMPDIR/root/etc/X11/xorg.conf.d/00-keyboard.conf
    echo 'EndSection' >> $TMPDIR/root/etc/X11/xorg.conf.d/00-keyboard.conf
    sed -i s/"us"/"$X11KEYMAP"/ $TMPDIR/root/etc/X11/xorg.conf.d/00-keyboard.conf
    fi
    if [[ "$EDITION" = "sway" ]]; then
    sed -i s/"us"/"$X11KEYMAP"/ $TMPDIR/root/etc/sway/inputs/default-keyboard 1> /dev/null 2>&1
    fi
    echo "$HOSTNAME" | tee --append $TMPDIR/root/etc/hostname 1> /dev/null 2>&1
    sed -i s/"enable systemd-resolved.service"/"#enable systemd-resolved.service"/ $TMPDIR/root/usr/lib/systemd/system-preset/90-systemd.preset

    echo "Correcting permissions from overlay..."
    chown -R root:root $TMPDIR/root/etc
    if [[ "$EDITION" != "minimal" && "$EDITION" != "server" ]]; then
        chown root:polkitd $TMPDIR/root/etc/polkit-1/rules.d
    elif [[ "$EDITION" = "cubocore" ]]; then
        cp $TMPDIR/root/usr/share/applications/corestuff.desktop $TMPDIR/root/etc/xdg/autostart/
    fi
    
    if [[ "$FSTYPE" = "btrfs" ]]; then
        info "Adding btrfs support to system..."
        echo "LABEL=ROOT_MNJRO / btrfs  subvol=@,compress=zstd,defaults,noatime  0  0" >> $TMPDIR/root/etc/fstab
        echo "LABEL=ROOT_MNJRO /home btrfs  subvol=@home,compress=zstd,defaults,noatime  0  0" >> $TMPDIR/root/etc/fstab
        sed -i '/^MODULES/{s/)/ btrfs)/}' $TMPDIR/root/etc/mkinitcpio.conf
        $NSPAWN $TMPDIR/root mkinitcpio -P 1> /dev/null 2>&1
        if [ -f $TMPDIR/root/boot/extlinux/extlinux.conf ]; then
            sed -i 's/APPEND/& rootflags=subvol=@/' $TMPDIR/root/boot/extlinux/extlinux.conf
        elif [ -f $TMPDIR/root/boot/boot.ini ]; then
            sed -i 's/setenv bootargs "/&rootflags=subvol=@ /' $TMPDIR/root/boot/boot.ini
        elif [ -f $TMPDIR/root/boot/uEnv.ini ]; then
            sed -i 's/setenv bootargs "/&rootflags=subvol=@ /' $TMPDIR/root/boot/uEnv.ini
        elif [ -f $TMPDIR/root/boot/cmdline.txt ]; then
            sed -i 's/root=LABEL=ROOT_MNJRO/& rootflags=subvol=@/' $TMPDIR/root/boot/cmdline.txt
        #elif [ -f $TMPDIR/root/boot/boot.txt ]; then
        #    sed -i 's/setenv bootargs/& rootflags=subvol=@/' $TMPDIR/root/boot/boot.txt
        #    $NSPAWN $TMPDIR/root mkimage -A arm -O linux -T script -C none -n "U-Boot boot script" -d /boot/boot.txt /boot/boot.scr
        fi

    fi

    
    if [[ "$CRYPT" = "yes" ]]; then
    tweakinitrd_crypt
    fi
    
    info "Cleaning install for unwanted files..."
    umount $TMPDIR/root/var/cache/pacman/pkg
    rm -rf $TMPDIR/root/usr/bin/qemu-aarch64-static
    rm -rf $TMPDIR/root/var/cache/pacman/pkg/*
    rm -rf $TMPDIR/root/var/log/*
    rm -rf $TMPDIR/root/etc/*.pacnew
    rm -rf $TMPDIR/root/usr/lib/systemd/system/systemd-firstboot.service
    rm -rf $TMPDIR/root/etc/machine-id
    
    # Remove temp files on host
    rm -rf $TMPDIR/user $TMPDIR/password $TMPDIR/rootpassword
    rm -rf $TMPDIR/Manjaro-ARM-$ARCH-latest.tar.gz*

    msg "$DEVICE $EDITION install complete"
}

prepare_card () {
    msg "Getting $SDCARD ready with $FSTYPE for $DEVICE..."
        # umount SD card
        umount ${SDCARD}${SDDEV}1 1> /dev/null 2>&1
        umount ${SDCARD}${SDDEV}2 1> /dev/null 2>&1
        # Create partitions
        #Clear first 32mb
        dd if=/dev/zero of=${SDCARD} bs=1M count=32 1> /dev/null 2>&1
        #remove previous partitions
        for v_partition in $(parted -s $SDCARD print|awk '/^ / {print $1}')
		do
			parted -s $SDCARD rm ${v_partition} 1> /dev/null 2>&1
		done
        #partition with boot and root
        case "$DEVICE" in
            oc2|on2|on2-plus|oc4|ohc4|vim1|vim2|vim3|gtking-pro|gsking-x|edgev|rpi4|pinephone)
            parted -s $SDCARD mklabel msdos 1> /dev/null 2>&1
            ;;
            *)
            parted -s $SDCARD mklabel gpt 1> /dev/null 2>&1
            ;;
        esac
        parted -s $SDCARD mkpart primary fat32 32M 256M 1> /dev/null 2>&1
        sleep 5
        START=`cat /sys/block/$DEV_NAME/${DEV_NAME}${SDDEV}1/start`
        SIZE=`cat /sys/block/$DEV_NAME/${DEV_NAME}${SDDEV}1/size`
        END_SECTOR=$(expr $START + $SIZE)
        case "$FSTYPE" in
            btrfs)
                parted -s $SDCARD mkpart primary btrfs "${END_SECTOR}s" 100% 1> /dev/null 2>&1
                partprobe $SDCARD 1> /dev/null 2>&1
                mkfs.vfat "${SDCARD}${SDDEV}1" -n BOOT_MNJRO 1> /dev/null 2>&1
				mkfs.btrfs -m single -L ROOT_MNJRO -f "${SDCARD}${SDDEV}2" 1> /dev/null 2>&1

                mkdir -p $TMPDIR/root
                mkdir -p $TMPDIR/boot
                # Do subvolumes
                mount -o compress=zstd "${SDCARD}${SDDEV}2" $TMPDIR/root
                btrfs su cr $TMPDIR/root/@ 1> /dev/null 2>&1
                btrfs su cr $TMPDIR/root/@home 1> /dev/null 2>&1
                umount $TMPDIR/root
                mount -o compress=zstd,subvol=@ "${SDCARD}${SDDEV}2" $TMPDIR/root
                mkdir -p $TMPDIR/root/home
                mount -o compress=zstd,subvol=@home "${SDCARD}${SDDEV}2" $TMPDIR/root/home
                mount ${SDCARD}${SDDEV}1 $TMPDIR/boot
                ;;
            ext4)
                parted -s $SDCARD mkpart primary ext4 "${END_SECTOR}s" 100% 1> /dev/null 2>&1
                partprobe $SDCARD 1> /dev/null 2>&1
                mkfs.vfat "${SDCARD}${SDDEV}1" -n BOOT_MNJRO 1> /dev/null 2>&1

                if [[ "$CRYPT" != "yes" ]]; then
                    mkfs.ext4 -O ^metadata_csum,^64bit "${SDCARD}${SDDEV}2" -L ROOT_MNJRO 1> /dev/null 2>&1
                else
					info "Create encryption password:"
                    cryptsetup luksFormat -q "${SDCARD}${SDDEV}2"
                    info "Confirm encryption password:"
                    cryptsetup open "${SDCARD}${SDDEV}2" ROOT_MNJRO
                    mkfs.ext4 -O ^metadata_csum,^64bit /dev/mapper/ROOT_MNJRO 1> /dev/null 2>&1
                fi

                mkdir -p $TMPDIR/root
                mkdir -p $TMPDIR/boot
                mount ${SDCARD}${SDDEV}1 $TMPDIR/boot
                if [[ "$CRYPT" != "yes" ]]; then
                    mount ${SDCARD}${SDDEV}2 $TMPDIR/root
                else
                    [ ! -e /dev/mapper/ROOT_MNJRO ] && cryptsetup open "${SDCARD}${SDDEV}2" ROOT_MNJRO
                    mount /dev/mapper/ROOT_MNJRO $TMPDIR/root
                fi
                ;;
        esac
}

cleanup () {
    msg "Writing bootloader and cleaning up after install..."
    # Move boot files
    mv $TMPDIR/root/boot/* $TMPDIR/boot
    # Flash bootloader
    case "$DEVICE" in
    oc2)
        dd if=$TMPDIR/boot/bl1.bin.hardkernel of=${SDCARD} conv=fsync bs=1 count=442 1> /dev/null 2>&1
        dd if=$TMPDIR/boot/bl1.bin.hardkernel of=${SDCARD} conv=fsync bs=512 skip=1 seek=1 1> /dev/null 2>&1
        dd if=$TMPDIR/boot/u-boot.gxbb of=${SDCARD} conv=fsync bs=512 seek=97 1> /dev/null 2>&1
        ;;
    on2|on2-plus|oc4)
        dd if=$TMPDIR/boot/u-boot.bin of=${SDCARD} conv=fsync,notrunc bs=512 seek=1 1> /dev/null 2>&1
        ;;
    vim1|vim2|vim3)
        dd if=$TMPDIR/boot/u-boot.bin of=${SDCARD} conv=fsync bs=1 count=442 1> /dev/null 2>&1
        dd if=$TMPDIR/boot/u-boot.bin of=${SDCARD} conv=fsync bs=512 skip=1 seek=1 1> /dev/null 2>&1
        ;;
    pinebook|pine64-lts|pine64|pinetab|pine-h64)
        dd if=$TMPDIR/boot/u-boot-sunxi-with-spl-$DEVICE.bin of=${SDCARD} conv=fsync bs=128k seek=1 1> /dev/null 2>&1
        ;;
    pinephone)
        dd if=$TMPDIR/boot/u-boot-sunxi-with-spl-$DEVICE.bin of=${SDCARD} conv=fsync bs=8k seek=1 1> /dev/null 2>&1
        ;;
    pbpro|rockpro64|rockpi4b|rockpi4c|nanopc-t4|rock64|roc-cc)
        dd if=$TMPDIR/boot/idbloader.img of=${SDCARD} seek=64 conv=notrunc,fsync 1> /dev/null 2>&1
        dd if=$TMPDIR/boot/u-boot.itb of=${SDCARD} seek=16384 conv=notrunc,fsync 1> /dev/null 2>&1
        ;;
    esac

	if [[ "$CRYPT" = "yes" ]]; then
	post_crypt
	fi
    
    # edit boot files and fstab
    # set UUID for boot partition in fstab
    BOOT_PARTUUID=$(lsblk -o NAME,PARTUUID | grep ${DEV_NAME}${SDDEV}1 | awk '{print $2}')
    sed -i "s/LABEL=BOOT_MNJRO/PARTUUID=$BOOT_PARTUUID/g" $TMPDIR/root/etc/fstab
    echo "Set boot partition to $BOOT_PARTUUID in /etc/fstab..."
    
	# Change boot script and fstab to root partition UUID
    ROOT_PARTUUID=$(lsblk -o NAME,PARTUUID | grep ${DEV_NAME}${SDDEV}2 | awk '{print $2}')
    if [ -f $TMPDIR/boot/extlinux/extlinux.conf ]; then
    sed -i "s/LABEL=ROOT_MNJRO/PARTUUID=$ROOT_PARTUUID/g" $TMPDIR/boot/extlinux/extlinux.conf
        elif [ -f $TMPDIR/boot/boot.ini ]; then
        sed -i "s/LABEL=ROOT_MNJRO/PARTUUID=$ROOT_PARTUUID/g" $TMPDIR/boot/boot.ini
        elif [ -f $TMPDIR/boot/uEnv.ini ]; then
        sed -i "s/LABEL=ROOT_MNJRO/PARTUUID=$ROOT_PARTUUID/g" $TMPDIR/boot/uEnv.ini
        elif [ -f $TMPDIR/boot/cmdline.txt ]; then
        sed -i "s/LABEL=ROOT_MNJRO/PARTUUID=$ROOT_PARTUUID/g" $TMPDIR/boot/cmdline.txt
	fi
	echo "Set root partition to $ROOT_PARTUUID in the relevant boot script..."
    sed -i "s/LABEL=ROOT_MNJRO/PARTUUID=$ROOT_PARTUUID/g" $TMPDIR/root/etc/fstab
    echo "Set root partition to $ROOT_PARTUUID in /etc/fstab if applicable..."
    sync


    #clean up
    if [[ "$FSTYPE" = "btrfs" ]]; then
        umount $TMPDIR/root/home
        umount $TMPDIR/root
        umount $TMPDIR/boot
    else
        umount $TMPDIR/root
        umount $TMPDIR/boot
		if [[ "$CRYPT" = "yes" ]]; then
			cryptsetup close /dev/mapper/ROOT_MNJRO
		fi
    fi
		partprobe $SDCARD 1> /dev/null 2>&1
		
		info "If you get an error stating 'failed to preserve ownership ... Operation not permitted', it's expected, since the boot partition is FAT32 and does not support ownership permissions..."
}

tweakinitrd_crypt () {
    case "$DEVICE" in
    pbpro)
      # Use the proper mkinitcpio.
      cat << EOF > ${TMPDIR}/root/etc/mkinitcpio.conf
MODULES=(panfrost rockchipdrm drm_kms_helper hantro_vpu analogix_dp rockchip_rga panel_simple arc_uart cw2015_battery i2c-hid iscsi_boot_sysfs jsm pwm_bl uhid)
BINARIES=()
FILES=()
HOOKS=(base udev keyboard autodetect keymap modconf block encrypt lvm2 filesystems fsck)
COMPRESSION="cat"
EOF

      # Install lvm2, this will trigger the cpio rebuild
      $NSPAWN $TMPDIR/root pacman -Syyu lvm2 --noconfirm
      ;;
    esac
}

post_crypt () {
    # Get the UUID
    UUID=$(blkid -s UUID -o value "${SDCARD}${SDDEV}2")

    # Modify the /boot/extlinux/extlinux.conf to match our needs
    case "$DEVICE" in
    pbpro)
      # NOTE: I've tried to only modify the cryptdevice and root parameters but bootsplash and console=ttyS2 prevents to show the password prompt
      # TODO: Need to add plymouth support
      sed -i -e "s!APPEND.*!APPEND initrd=/initramfs-linux.img console=tty1 cryptdevice=UUID=${UUID}:ROOT_MNJRO root=/dev/mapper/ROOT_MNJRO rw rootwait!g" ${TMPDIR}/boot/extlinux/extlinux.conf
      ;;
    esac

    # Generate the /etc/crypttab file
    echo "ROOT_MNJRO   UUID=${UUID}    none            luks,discard" > ${TMPDIR}/root/etc/crypttab
}

# Using Dialog to ask for user input for variables
if [ ! -z "${DEVICE}" ]; then
DEVICE=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
        --menu "Choose a device:" 20 75 10 \
        "rpi4"          "Raspberry Pi 4/400/3+/3" \
        "pbpro"         "Pinebook Pro" \
        "rockpro64"     "RockPro64" \
        "rockpi4b"      "Rock Pi 4B" \
        "rockpi4c"      "Rock Pi 4C" \
        "on2"           "Odroid N2" \
        "on2-plus"      "Odroid N2+" \
        "oc4"           "Odroid C4" \
        "oc2"           "Odroid C2" \
        "pinebook"      "Pinebook" \
        "pine64-lts"    "Pine64-LTS / Sopine" \
        "pine64"        "Pine64+" \
        "pine-h64"      "Pine H64" \
        "rock64"        "Rock64" \
        "roc-cc"        "LibreComputer Renegade" \
        "nanopc-t4"     "NanoPC T4" \
        "vim3"          "Khadas Vim 3" \
        "vim2"          "Khadas Vim 2" \
        "vim1"          "Khadas Vim 1" \
        "gt1-ultimate"  "Beelink GT1 Ultimate" \
        3>&1 1>&2 2>&3 3>&-)
fi


#The if statement makes sure that the user has put in something in the previous prompt. If not (left blank or pressed cancel) the script will end
if [ ! -z "${EDITION}" ]; then
    EDITION=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
        --menu "Choose an edition:" 20 75 10 \
        "minimal"       "Minimal Edition            (only CLI)" \
        "kde-plasma"    "Full KDE/Plasma Desktop    (full featured)" \
        "xfce"          "Full XFCE desktop and apps (full featured)" \
        "mate"          "Full MATE desktop and apps (lightweight)" \
        "gnome"         "Full Gnome desktop and apps (EXPERIMANTAL)" \
        "sway"          "Minimal Sway WM with apps  (very light)" \
        "lxqt"          "Full LXQT Desktop and apps (lightweight)" \
        "i3"            "Mininal i3 WM with apps    (very light)" \
        "server"        "Minimal with LAMP and Docker (only cli)" \
        "budgie"        "Full Budgie desktop (EXPERIMENTAL))" \
        3>&1 1>&2 2>&3 3>&-) 

else 
	clear
	exit 1
fi


if [ ! -z "${USER}" ]; then
	USER=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
	--inputbox "Enter the username you want:
(usernames must be all lowercase and first character may not be a number)" 10 90 \
	3>&1 1>&2 2>&3 3>&-)
    if [[ "$USER" =~ [A-Z] ]] || [[ "$USER" =~ ^[0-9] ]] || [[ "$USER" == *['!'@#\$%^\&*()_+]* ]]; then
    clear
    msg "Configuration aborted! Username contained invalid characters."
    exit 1
    fi
else 
	clear
	exit 1
fi

if [ ! -z "${USERGROUPS}" ]
then
USERGROUPS=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
    --inputbox "Enter additional groups for $USER in a comma seperated list: (empty if none)
(default: wheel,sys,audio,input,video,storage,lp,network,users,power)" 10 90 \
        3>&1 1>&2 2>&3 3>&- \
	)
else 
	clear
	exit 1
fi

if [ ! -z "${FULLNAME}" ]
then
FULLNAME=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
    --inputbox "Enter desired Full Name for $USER:" 8 50 \
        3>&1 1>&2 2>&3 3>&- \
	)
else
    clear
    exit 1
fi


if [ ! -z "${PASSWORD}" ]; then
	PASSWORD=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
	--insecure --passwordbox "Enter new Password for $USER:" 8 50 \
	3>&1 1>&2 2>&3 3>&- \
	)
else 
	clear
	exit 1
fi

if [ ! -z "${CONFIRMPASSWORD}" ]; then
	CONFIRMPASSWORD=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
	--insecure --passwordbox "Confirm new Password for $USER:" 8 50 \
	3>&1 1>&2 2>&3 3>&- \
	)
else 
	clear
	exit 1
fi

if [[ "$PASSWORD" != "$CONFIRMPASSWORD" ]]; then
	clear
	msg "User passwords do not match! Please restart the installer and try again."
	exit 1
fi

if [ ! -z "${ROOTPASSWORD}" ]; then
	ROOTPASSWORD=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
	--insecure --passwordbox "Enter new Root Password:" 8 50 \
	3>&1 1>&2 2>&3 3>&- \
	)
else 
	clear
	exit 1
fi

if [ ! -z "${CONFIRMROOTPASSWORD}" ]; then
	CONFIRMROOTPASSWORD=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
	--insecure --passwordbox "Confirm new Root Password:" 8 50 \
	3>&1 1>&2 2>&3 3>&- \
	)
else 
	clear
	exit 1
fi

if [[ "$ROOTPASSWORD" != "$CONFIRMROOTPASSWORD" ]]; then
	clear
	msg "Root passwords do not match! Please restart the installer and try again."
	exit 1
fi

if [ ! -z "${SDCARD}" ]
then

# simple command to put the results of lsblk (just the names of the devices) into an array and make that array populate the options	
	let i=0
	W=()
	while read -r line; do
		let i=$i+1
		W+=($line "")
	done < <( lsblk -dn -o NAME )
	SDCARD=$(dialog --title "Manjaro ARM Installer v${VERSION}" \
	--menu "Choose your SDCard/eMMC/USB - Be sure the correct drive is selected! 
WARNING! This WILL destroy the data on it!" 20 50 10 \
	"${W[@]}" 3>&2 2>&1 1>&3)

# add /dev/ to the selected option above
	DEV_NAME=$SDCARD
	SDCARD=/dev/$SDCARD
	SDTYP=${SDCARD:5:2}
else 
	clear
	exit 1
fi

if [[ "$SDTYP" = "sd" ]]; then
	SDDEV=""
elif [[ "$SDTYP" = "mm" ]]; then
	SDDEV="p"
else 
	clear
	exit 1
fi

if [ ! -z "${FSTYPE}" ]; then
    FSTYPE=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
        --menu "Choose a filesystem:" 10 90 10 \
        "ext4"       "Regular ext4 filesystem" \
        "btrfs"      "Uses btrfs for root partition and makes / and /home subvolumes" \
        3>&1 1>&2 2>&3 3>&-) 

else 
	clear
	exit 1
fi

if [[ "$DEVICE" = "pbpro" ]] && [[ "$FSTYPE" != "btrfs" ]]; then
	CRYPT=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
		--menu "[Experimental!] Do you want encryption on root partition?" 10 90 10 \
		"no"		"No, thanks" \
		"yes"		"Yes, please" \
		3>&1 1>&2 2>&3 3>&-)
fi

if [[ -d /dev/mapper/ROOT_MNJRO ]] && [[ "$CRYPT" = "yes" ]]; then
	clear
	exit 2
fi

if [ ! -z "${TIMEZONE}" ]; then
	let i=0
	W=()
	while read -r line; do
		let i=$i+1
		W+=($line "")
	done < <( timedatectl list-timezones )
	TIMEZONE=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
	--menu "Choose your timezone!" 20 50 15 \
	"${W[@]}" 3>&1 1>&2 2>&3 3>&- \
	)
else 
	clear
	exit 1
fi


if [ ! -z "${LOCALE}" ]; then
	let i=0
	W=()
	while read -r line; do
		let i=$i+1
		W+=($line "")
	done < <( cat /etc/locale.gen | grep "UTF-8" | tail -n +2 | sed -e 's/^#*//' | awk '{print $1}' )
	LOCALE=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
		--menu "Choose your locale!" 20 50 15 \
		"${W[@]}" 3>&1 1>&2 2>&3 3>&- \
		)
else 
	clear
	exit 1
fi

if [ ! -z "${CLIKEYMAP}" ]; then
	let i=0
	W=()
	while read -r line; do
		let i=$i+1
		W+=($line "")
	done < <( localectl list-keymaps )
	CLIKEYMAP=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
		--menu "Choose your TTY keyboard layout:" 20 50 15 \
		"${W[@]}" 3>&1 1>&2 2>&3 3>&- \
	)
else 
	clear
	exit 1
fi

if [[ "${EDITION}" != "minimal" ]]; then
if [ ! -z "${X11KEYMAP}" ]; then
	let i=0
	W=()
	while read -r line; do
		let i=$i+1
		W+=($line "")
	done < <( localectl list-x11-keymap-layouts )
	X11KEYMAP=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
		--menu "Choose your X11 keyboard layout:" 20 50 15 \
		"${W[@]}" 3>&1 1>&2 2>&3 3>&- \
	)
else 
	clear
	exit 1
fi
fi

if [ ! -z "${HOSTNAME}" ]; then
	HOSTNAME=$(dialog --clear --title "Manjaro ARM Installer v${VERSION}" \
	--inputbox "Enter desired hostname for this system:" 8 50 \
	3>&1 1>&2 2>&3 3>&- \
	)
else 
	clear
	exit 1
fi

if [ ! -z "$HOSTNAME" ]; then
	dialog --clear --title "Manjaro ARM Installer" \
    --yesno "Is the below information correct:
    Device = $DEVICE
    Edition = $EDITION
    Username = $USER
    Full Username = $FULLNAME
    Additional usergroups = $USERGROUPS
    Password for $USER = (password hidden)
    Password for root = (password hidden)
    SDCard/eMMC/USB = $SDCARD
    Filesystem = $FSTYPE
    Encryption (only on select devices) = $CRYPT
    Timezone = $TIMEZONE
    Locale = $LOCALE
    TTY Keyboard layout = $CLIKEYMAP
    X11 Keyboard layout = $X11KEYMAP
    Hostname = $HOSTNAME" 25 70 \
    3>&1 1>&2 2>&3 3>&-
else
	clear
	exit 1
fi

response=$?
case $response in
   0) clear; msg "Proceeding....";;
   1) clear; msg "Installation aborted...."; exit 1;;
   2) clear; msg "Installation not possible from an encrypted system..."; exit 1;;
   255) clear; msg "Installation aborted..."; exit 1;;
esac


# get the profiles
installer_getarmprofiles

#Package lists
PKG_DEVICE=$(grep "^[^#;]" $TMPDIR/arm-profiles/devices/$DEVICE | awk '{print $1}')
PKG_EDITION=$(grep "^[^#;]" $TMPDIR/arm-profiles/editions/$EDITION | awk '{print $1}')
SRV_EDITION=$(grep "^[^#;]" $TMPDIR/arm-profiles/services/$EDITION | awk '{print $1}')
cat $TMPDIR/arm-profiles/services/$EDITION | sed -e '/^#/d' -e '/>pinephone/d' >$srv_list


# Commands
timer_start=$(get_timer)

prepare_card
create_install
cleanup
show_elapsed_time "${FUNCNAME}" "${timer_start}"
sync
