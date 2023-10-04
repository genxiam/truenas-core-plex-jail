#!/bin/sh

# Install Transmission in a TrueNAS Core 13.1-RELEASE jail
# Get the latest version from https://github.com/genxiam/truenas-core-plex-jail.git
# Usage: ./install_transmission.sh -i 192.168.0.100 -g 192.168.0.1 -d /mnt/tank/torrents

# Init user variables
JAIL_IP=""                # -i 192.168.0.100
GW_IP=""                  # -g 192.168.0.1
NETMASK=24                # -n 24
DATA_PATH=""              # -d /mnt/tank/torrents
JAIL_NAME="transmission"  # -j transmission

# Init script variables
VERSION="$(freebsd-version | cut -d - -f -1)-RELEASE"
TM_PKG="transmission-daemon"
TM_ID="921"
TM_JSON="/usr/local/etc/transmission/home/settings.json"

# Roots Bloody Roots 🤘
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

# Validate an IPv4 address format
is_valid_ip() {
  local ip="$1"
  local regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"

  if echo "$ip" | grep -Eq "$regex"; then
    # Ensure each number is between 0-255
    local IFS="."
      set -- $ip
      [ "$1" -le 255 ] && [ "$2" -le 255 ] && [ "$3" -le 255 ] && [ "$4" -le 255 ]
    else
      return 1
  fi
}

# Validate an IPv4 netmask in integer format
is_valid_netmask() {
  local mask="$1"

  # Check if netmask is an integer between 0 and 32
  if echo "$mask" | grep -E -q "^[0-9]+$"; then
    # Check if mask is between 0 and 32
    if [ "$mask" -ge 0 ] && [ "$mask" -le 32 ]; then
      return 0
    fi
  fi
  return 1
}

# Process command line options
while getopts ":i:g:n:d:j:" opt; do
  case $opt in
    i)
      JAIL_IP=$OPTARG
      ;;
    g)
      GW_IP=$OPTARG
      ;;
    n)
      NETMASK=$OPTARG
      ;;
    d)
      DATA_PATH=$OPTARG
      ;;
    j)
      JAIL_NAME=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

# Check if the data path is specified
if [ -z "${DATA_PATH}" ]; then
  echo "Please specify where Transmission should store it's data, e.g. -d /mnt/tank/torrents"
  exit 1
fi

# Check if the jail name is specified
if [ -z "${JAIL_NAME}" ]; then
  echo "Please specify the name of the jail, e.g. -j transmission"
  exit 1
fi

# Check if JAIL_IP is valid
if ! is_valid_ip "$JAIL_IP"; then
  echo "The jail ip address $JAIL_IP is not valid, e.g. -i 192.168.0.100" >&2
  exit 1
fi

# Check if GW_IP is valid
if ! is_valid_ip "$GW_IP"; then
  echo "The gateway ip address $GW_IP is not valid, e.g. -g 192.168.0.1" >&2
  exit 1
fi

# Check if NETMASK is valid
if ! is_valid_netmask "$NETMASK"; then
  echo "The netmask $NETMASK is not valid, e.g. -n 24" >&2
  exit 1
fi

# Create iocage jail
echo "Creating ${JAIL_NAME} jail. This may take a while."
JAIL_EXISTS="$(iocage list | grep "${JAIL_NAME}")"
if [ -n "${JAIL_EXISTS}" ]; then
  echo "Error: Jail with name ${JAIL_NAME} already exists"
  exit 1
fi
if ! iocage create -b -n "${JAIL_NAME}" -r "${VERSION}" ip4_addr="vnet0|${JAIL_IP}/${NETMASK}" defaultrouter="${GW_IP}" host_hostname="${JAIL_NAME}" vnet=1 boot=0
then
  echo "Error: Failed to create ${JAIL_NAME} jail"
  exit 1
fi
echo "Starting ${JAIL_NAME} jail for the first time"
iocage start "${JAIL_NAME}"

# Set pkg repos from quarterly to latest and configure pkg.conf
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/etc/pkg/repos
iocage exec "${JAIL_NAME}" cp /etc/pkg/FreeBSD.conf /usr/local/etc/pkg/repos/
iocage exec "${JAIL_NAME}" sed -i '' "s/quarterly/latest/" /usr/local/etc/pkg/repos/FreeBSD.conf
iocage exec "${JAIL_NAME}" "echo 'ASSUME_ALWAYS_YES = true;' > /usr/local/etc/pkg.conf"

# Group check and creation
GRP_EXISTS=$(midclt call group.query "[[\"gid\", \"=\", ${TM_ID}]]")
if [ -z "$GRP_EXISTS" ] || [ "$GRP_EXISTS" == "[]" ]; then
  midclt call group.create "{\"gid\": ${TM_ID}, \"name\": \"transmission\"}" > /dev/null 2>&1
  echo "Created transmission group with GID ${TM_ID}"
fi

# User check and creation
USR_EXISTS=$(midclt call user.query "[[\"uid\", \"=\", ${TM_ID}]]")
if [ -z "$USR_EXISTS" ] || [ "$USR_EXISTS" == "[]" ]; then
  GRP_EXISTS=$(midclt call group.query "[[\"gid\", \"=\", ${TM_ID}]]")
  GRP_ID=$(echo "$GRP_EXISTS" | jq -r '.[0].id')
  midclt call user.create "{
    \"uid\": ${TM_ID},
    \"username\": \"transmission\",
    \"full_name\": \"Transmission\",
    \"group\": ${GRP_ID},
    \"password_disabled\": true,
    \"home\": \"/nonexistent\",
    \"shell\": \"/usr/sbin/nologin\"
  }" > /dev/null 2>&1
  echo "Created transmission user with UID ${TM_ID}"
fi

# Create and mount data folders
mkdir -p "${DATA_PATH}/complete"
mkdir -p "${DATA_PATH}/incomplete"
chown -R ${TM_ID}:${TM_ID} "${DATA_PATH}"
iocage fstab -a "${JAIL_NAME}" "${DATA_PATH}" /media nullfs rw 0 0
echo "Added mount point for ${DATA_PATH} -> /media folder"

# Install Transmission
echo
echo "Installing ${TM_PKG}. This may take a while."
if ! iocage exec "${JAIL_NAME}" pkg install "${TM_PKG}"
then
  echo "Error: ${TM_PKG} installation failed"
	iocage stop "${JAIL_NAME}"
	iocage destroy -f "${JAIL_NAME}"
	exit 1
fi
echo "Installed ${TM_PKG} successfully!"

# Undo pkg.conf changes
iocage exec "${JAIL_NAME}" sed -i '' "s/^ASSUME_ALWAYS_YES = true;/#ASSUME_ALWAYS_YES = false;/" /usr/local/etc/pkg.conf

# Start transmission on jail boot, enforce download-dir and configure to check for updates monthly
iocage exec "${JAIL_NAME}" sysrc transmission_enable="YES"
iocage exec "${JAIL_NAME}" sysrc transmission_download_dir="/media/complete"
iocage exec "${JAIL_NAME}" "echo '0 4 1 * * pkg upgrade -y && service transmission restart' | crontab -"
echo "Configured to check for latest updates on a monthly schedule"

# Create default settings.json
iocage exec "${JAIL_NAME}" service transmission start
iocage exec "${JAIL_NAME}" service transmission stop

# Update Transmission settings
iocage exec "${JAIL_NAME}" sed -i '' 's|"/usr/local/etc/transmission/home/Downloads"|"/media/complete"|' "${TM_JSON}"
iocage exec "${JAIL_NAME}" sed -i '' 's|"//Downloads"|"/media/incomplete"|' "${TM_JSON}"
iocage exec "${JAIL_NAME}" sed -i '' "s|\"incomplete-dir-enabled\": false|\"incomplete-dir-enabled\": true,\n    \"watch-dir\": \"/media\",\n    \"watch-dir-enabled\": true|" "${TM_JSON}"
iocage exec "${JAIL_NAME}" sed -i '' 's|"rename-partial-files": false|"rename-partial-files": true|' "${TM_JSON}"
iocage exec "${JAIL_NAME}" sed -i '' 's|"rpc-whitelist-enabled": true|"rpc-whitelist-enabled": false|' "${TM_JSON}"

# Restart the jail
iocage restart "${JAIL_NAME}"

echo
echo "Installation Complete!"
echo
echo "Make sure that ${DATA_PATH} ACLs allow transmission user/group access"
echo
echo "Configure Transmission at: http://$JAIL_IP:9091/transmission/web"
echo
