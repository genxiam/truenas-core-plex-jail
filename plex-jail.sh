#!/bin/sh

# Install Plex Media Server in a TrueNAS Core 13.1-RELEASE jail
# Get the latest version from https://github.com/genxiam/truenas-core-plex-jail.git
# Usage: ./plex-jail.sh -ph -i 192.168.0.100 -g 192.168.0.1 -d /mnt/tank/plex_data -m /mnt/tank/media

# Init user variables
USE_PLEXPASS=0      # -p
USE_IQSV=0          # -h
JAIL_IP=""          # -i 192.168.0.100
GW_IP=""            # -g 192.168.0.1
NETMASK=24          # -n 24
PLEX_DATA_PATH=""   # -d /mnt/tank/plex_data
PLEX_MEDIA_PATH=""  # -m /mnt/tank/media
JAIL_NAME="plex"    # -j plex

# Init script variables
VERSION="$(freebsd-version | cut -d - -f -1)-RELEASE"
ROOT_SCRIPT="/root/plex-ruleset.sh"
DRIVER="i915kms.ko"
IQSV_RULESET="10"
DEVFS_RULESET=""
PLEX_PKG="plexmediaserver"
PLEX_ID="972"

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

# Create a POSTINIT script that modifies /etc/devfs.rules and loads the iGPU driver
create_root_script() {
  IGPU_MODEL=$(lspci -q | grep Intel | grep Graphics)
  if [ -z "${IGPU_MODEL}" ] ; then
    echo "Error: Intel Quick Sync Video capable iGPU could not be found"
    return 1
  else
    echo "Found ${IGPU_MODEL}"
    if ! kldstat | grep -q "${DRIVER}" ; then
      kldload "/boot/modules/${DRIVER}"
      if ! kldstat | grep -q "${DRIVER}" ; then
        echo "Error: Unable to load Intel iGPU driver"
        return 1
      else
        echo "Intel iGPU driver loaded"
      fi
    else
      echo "Intel iGPU driver already present"
    fi
  fi
  if [ ! -f "${ROOT_SCRIPT}" ] ; then
    echo "Creating script ${ROOT_SCRIPT}"
    cat > "${ROOT_SCRIPT}" <<EOF
#!/bin/sh

echo '[devfsrules_bpfjail=101]
add path 'bpf*' unhide

[plex_drm=$IQSV_RULESET]
add include \$devfsrules_hide_all
add include \$devfsrules_unhide_basic
add include \$devfsrules_unhide_login
add include \$devfsrules_jail
add include \$devfsrules_bpfjail
add path 'dri*' unhide
add path 'dri/*' unhide
add path 'drm*' unhide
add path 'drm/*' unhide
' >> /etc/devfs.rules

service devfs restart

kldload /boot/modules/${DRIVER}
EOF
    chmod +x "${ROOT_SCRIPT}"
  fi
  if [ -z "$(devfs rule -s ${IQSV_RULESET} show)" ]; then
    echo "Executing script ${ROOT_SCRIPT}"
    "${ROOT_SCRIPT}" > /dev/null 2>&1
  fi
  if ! midclt call initshutdownscript.query | grep -q "${ROOT_SCRIPT}" ; then
    echo "Setting script ${ROOT_SCRIPT} to execute on system startup"
    midclt call initshutdownscript.create "{
      \"type\": \"SCRIPT\",
      \"script\": \"${ROOT_SCRIPT}\",
      \"when\": \"POSTINIT\",
      \"enabled\": true,
      \"timeout\": 10,
      \"comment\": \"Update devfs.rules and load ${DRIVER}\"
    }" > /dev/null 2>&1
  fi
  return 0
}

# Process command line options
while getopts ":phi:g:n:d:m:j:" opt; do
  case $opt in
    p)
      USE_PLEXPASS=1
      PLEX_PKG="plexmediaserver-plexpass"
      ;;
    h)
      USE_IQSV=1
      ;;
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
      PLEX_DATA_PATH=$OPTARG
      ;;
    m)
      PLEX_MEDIA_PATH=$OPTARG
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

# Check if plex_data path is specified
if [ -z "${PLEX_DATA_PATH}" ]; then
  echo "Please specify where Plex should store it's data, e.g. -d /mnt/tank/plex_data"
  exit 1
fi

# Check if media path is specified
if [ -z "${PLEX_MEDIA_PATH}" ]; then
  echo "Please specify where the media files are stored, e.g. -m /mnt/tank/media"
  exit 1
fi

# Check if the jail name is specified
if [ -z "${JAIL_NAME}" ]; then
  echo "Please specify the name of the jail, e.g. -j plex"
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

# Try to set up Intel Quick Sync Video hardware support
if [ ${USE_IQSV} -eq 1 ]; then
  if create_root_script; then
    echo "Configured Intel Quick Sync Video support successfully"
    DEVFS_RULESET="devfs_ruleset=${IQSV_RULESET}"
  else
    echo "Could not configure Intel Quick Sync Video support. Try without -h option."
    exit 1
  fi
fi

# Create iocage jail
echo "Creating Plex Media Server jail. This may take a while."
JAIL_EXISTS="$(iocage list | grep "${JAIL_NAME}")"
if [ -n "${JAIL_EXISTS}" ]; then
  echo "Error: Jail with name \"${JAIL_NAME}\" already exists"
  exit 1
fi
if ! iocage create -b -n "${JAIL_NAME}" -r "${VERSION}" ip4_addr="vnet0|${JAIL_IP}/${NETMASK}" defaultrouter="${GW_IP}" host_hostname="${JAIL_NAME}" vnet=1 boot=0 "${DEVFS_RULESET}"
then
  echo "Error: Failed to create Plex Media Server jail"
  exit 1
fi
echo "Starting jail ${JAIL_NAME} for the first time"
iocage start "${JAIL_NAME}"

# Set pkg repos from quarterly to latest and configure pkg.conf
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/etc/pkg/repos
iocage exec "${JAIL_NAME}" cp /etc/pkg/FreeBSD.conf /usr/local/etc/pkg/repos/
iocage exec "${JAIL_NAME}" sed -i '' "s/quarterly/latest/" /usr/local/etc/pkg/repos/FreeBSD.conf
iocage exec "${JAIL_NAME}" "echo 'ASSUME_ALWAYS_YES = true;' > /usr/local/etc/pkg.conf"

# Group check and creation
GRP_EXISTS=$(midclt call group.query "[[\"gid\", \"=\", ${PLEX_ID}]]")
if [ -z "$GRP_EXISTS" ] || [ "$GRP_EXISTS" == "[]" ]; then
  midclt call group.create "{\"gid\": ${PLEX_ID}, \"name\": \"plex\"}" > /dev/null 2>&1
  echo "Created plex group with GID ${PLEX_ID}"
fi

# User check and creation
USR_EXISTS=$(midclt call user.query "[[\"uid\", \"=\", ${PLEX_ID}]]")
if [ -z "$USR_EXISTS" ] || [ "$USR_EXISTS" == "[]" ]; then
  GRP_EXISTS=$(midclt call group.query "[[\"gid\", \"=\", ${PLEX_ID}]]")
  GRP_ID=$(echo "$GRP_EXISTS" | jq -r '.[0].id')
  midclt call user.create "{
    \"uid\": ${PLEX_ID},
    \"username\": \"plex\",
    \"full_name\": \"Plex Media Server\",
    \"group\": ${GRP_ID},
    \"password_disabled\": true,
    \"home\": \"/nonexistent\",
    \"shell\": \"/usr/sbin/nologin\"
  }" > /dev/null 2>&1
  echo "Created plex user with UID ${PLEX_ID}"
fi

# Create and mount data and media folders
mkdir -p "${PLEX_DATA_PATH}"
chown -R ${PLEX_ID}:${PLEX_ID} "${PLEX_DATA_PATH}"
iocage exec "${JAIL_NAME}" mkdir -p /plex
iocage fstab -a "${JAIL_NAME}" "${PLEX_DATA_PATH}" /plex nullfs rw 0 0
iocage fstab -a "${JAIL_NAME}" "${PLEX_MEDIA_PATH}" /media nullfs ro 0 0
echo "Added mount points for plex data and media folders"

# Install Plex Media Server
echo "Installing ${PLEX_PKG}. This may take a while."
if ! iocage exec "${JAIL_NAME}" pkg install "${PLEX_PKG}"
then
  echo "Error: ${PLEX_PKG} installation failed"
	iocage stop "${JAIL_NAME}"
	iocage destroy -f "${JAIL_NAME}"
	exit 1
fi
echo "Installed ${PLEX_PKG} successfully!"

# Undo pkg.conf changes
iocage exec "${JAIL_NAME}" sed -i '' "s/^ASSUME_ALWAYS_YES = true;/#ASSUME_ALWAYS_YES = false;/" /usr/local/etc/pkg.conf

# Add plex user to the video group
if [ ${USE_IQSV} -eq 1 ]; then
  iocage exec "${JAIL_NAME}" pw groupmod -n video -m plex
  echo "Added plex user to video group"
fi

# Start plex on jail boot and configure to check for updates monthly
if [ ${USE_PLEXPASS} -eq 1 ]; then
  iocage exec "${JAIL_NAME}" sysrc plexmediaserver_plexpass_enable="YES"
  iocage exec "${JAIL_NAME}" sysrc plexmediaserver_plexpass_support_path="/plex"
  iocage exec "${JAIL_NAME}" "echo '20 4 1 * * pkg upgrade -y && service plexmediaserver_plexpass restart' | crontab -"
else
  iocage exec "${JAIL_NAME}" sysrc plexmediaserver_enable="YES"
  iocage exec "${JAIL_NAME}" sysrc plexmediaserver_support_path="/plex"
  iocage exec "${JAIL_NAME}" "echo '20 4 1 * * pkg upgrade -y && service plexmediaserver restart' | crontab -"
fi
echo "Configured to check for latest updates on a monthly schedule"

# Restart the jail
iocage restart "${JAIL_NAME}"

echo
echo "Installation Complete!"
echo
echo "Make sure that ${PLEX_MEDIA_PATH} ACLs allow plex user/group access"
echo
echo "Configure your Plex Media Server at: http://$JAIL_IP:32400/web"
echo
