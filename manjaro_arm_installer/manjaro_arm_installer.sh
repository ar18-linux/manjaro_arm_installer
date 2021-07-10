#!/usr/bin/env bash
# ar18

# Prepare script environment
{
  # Script template version 2021-07-10_13:35:39
  # Get old shell option values to restore later
  shopt -s inherit_errexit
  IFS=$'\n' shell_options=($(shopt -op))
  set +x
  # Set shell options for this script
  set -o pipefail
  set -e
  # Make sure some modification to LD_PRELOAD will not alter the result or outcome in any way
  set +u
  LD_PRELOAD_old="${LD_PRELOAD}"
  set -u
  LD_PRELOAD=
  # Save old script_dir variable
  if [ ! -v ar18_old_script_dir_map ]; then
    declare -A -g ar18_old_script_dir_map
  fi
  set +u
  ar18_old_script_dir_map["$(readlink "${BASH_SOURCE[0]}")"]="${script_dir}"
  set -u
  # Save old script_path variable
  if [ ! -v ar18_old_script_path_map ]; then
    declare -A -g ar18_old_script_path_map
  fi
  set +u
  ar18_old_script_path_map["$(readlink "${BASH_SOURCE[0]}")"]="${script_path}"
  set -u
  # Determine the full path of the directory this script is in
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
  script_path="${script_dir}/$(basename "${0}")"
  #Set PS4 for easier debugging
  export PS4='\e[35m${BASH_SOURCE[0]}:${LINENO}: \e[39m'
  # Determine if this script was sourced or is the parent script
  if [ ! -v ar18_sourced_map ]; then
    declare -A -g ar18_sourced_map
  fi
  if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    ar18_sourced_map["${script_path}"]=1
  else
    ar18_sourced_map["${script_path}"]=0
  fi
  # Initialise exit code
  if [ ! -v ar18_exit_map ]; then
    declare -A -g ar18_exit_map
  fi
  ar18_exit_map["${script_path}"]=0
  # Save PWD
  if [ ! -v ar18_pwd_map ]; then
    declare -A -g ar18_pwd_map
  fi
  ar18_pwd_map["${script_path}"]="${PWD}"
  if [ ! -v ar18_parent_process ]; then
    export ar18_parent_process="$$"
  fi
  # Get import module
  if [ ! -v ar18.script.import ]; then
    mkdir -p "/tmp/${ar18_parent_process}"
    cd "/tmp/${ar18_parent_process}"
    curl -O https://raw.githubusercontent.com/ar18-linux/ar18_lib_bash/master/ar18_lib_bash/script/import.sh > /dev/null 2>&1 && . "/tmp/${ar18_parent_process}/import.sh"
    cd "${ar18_pwd_map["${script_path}"]}"
  fi
}
#################################SCRIPT_START##################################

ar18.script.import ar18.script.obtain_sudo_password
ar18.script.import ar18.script.execute_with_sudo
ar18.script.import ar18.pacman.install
ar18.script.import ar18.aur.install

ar18.script.obtain_sudo_password

ar18.pacman.install bash wget git systemd dialog parted libarchive \
  binfmt-qemu-static openssl gawk dosfstools polkit btrfs-progs cryptsetup \
  manjaro-arm-installer
  
ar18.aur.install binfmt-qemu-static
ar18.aur.install qemu-user-static-bin
  
ar18.script.execute_with_sudo systemctl restart systemd-binfmt

temp_dir="/tmp"

rm -rf "${temp_dir}/manjaro-arm-installer"
cp "${script_dir}/original_script.sh" "${temp_dir}/manjaro_install.sh"

. "${script_dir}/config/vars"

#cd "${temp_dir}"
#git clone https://gitlab.manjaro.org/manjaro-arm/applications/manjaro-arm-installer.git
#export CRYPT="yes"
ar18.script.execute_with_sudo sed -i 's/DEVICE=""/DEVICE="sdb"/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/EDITION=""/EDITION=""/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/USERGROUPS=""/USERGROUPS=""/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/FULLNAME=""/FULLNAME=""/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/PASSWORD=""/PASSWORD=""/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/CONFIRMPASSWORD=""/CONFIRMPASSWORD=""/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/CONFIRMROOTPASSWORD=""/CONFIRMROOTPASSWORD=""/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/ROOTPASSWORD=""/ROOTPASSWORD=""/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/SDCARD=""/SDCARD=""/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/SDTYP=""/SDTYP=""/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/SDDEV=""/SDDEV=""/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/DEV_NAME=""/DEV_NAME=""/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/FSTYPE=""/FSTYPE=""/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/TIMEZONE=""/TIMEZONE=""/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/LOCALE=""/LOCALE=""/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/HOSTNAME=""/HOSTNAME=""/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo sed -i 's/CRYPT=""/CRYPT=""/g' "manjaro-arm-installer/manjaro-arm-installer"

ar18.script.execute_with_sudo chmod +x "${temp_dir}/manjaro_install.sh"

# encryption not working workaround> https://archived.forum.manjaro.org/t/full-disk-encryption-with-luks-in-manjaro-arm-installer/139863/6
#ar18.script.execute_with_sudo sed -i 's/$CRYPT/y/g' "manjaro-arm-installer/manjaro-arm-installer"
ar18.script.execute_with_sudo -E bash -x "${temp_dir}/manjaro_install.sh"

##################################SCRIPT_END###################################
set +x
function clean_up(){
  rm -rf "/tmp/${ar18_parent_process}"
}
# Restore environment
{
  exit_script_path="${script_path}"
  # Restore script_dir and script_path
  script_dir="${ar18_old_script_dir_map["$(readlink "${BASH_SOURCE[0]}")"]}"
  script_path="${ar18_old_script_path_map["$(readlink "${BASH_SOURCE[0]}")"]}"
  # Restore LD_PRELOAD
  LD_PRELOAD="${LD_PRELOAD_old}"
  # Restore PWD
  cd "${ar18_pwd_map["${script_path}"]}"
  # Restore old shell values
  for option in "${shell_options[@]}"; do
    eval "${option}"
  done
}
# Return or exit depending on whether the script was sourced or not
{
  if [ "${ar18_sourced_map["${exit_script_path}"]}" = "1" ]; then
    return "${ar18_exit_map["${exit_script_path}"]}"
  else
    if [ "${ar18_parent_process}" = "$$" ]; then
      clean_up
    fi
    exit "${ar18_exit_map["${exit_script_path}"]}"
  fi
}

trap clean_up SIGINT
