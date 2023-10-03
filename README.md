# truenas-core-plex-jail
Scripted installation of a Plex Media Server in a TrueNAS Core 13.1-RELEASE jail

## Description
This script will:
- Try to enable Intel Quick Sync Video support i.e. enable hardware transcoding (results may vary)
- Create a `plex` jail and install Plex Media Server into it (with or without PlexPass)
- Create the `plex` user and group on the host system (needed for your media dataset ACLs)
- Configure Plex Media Server to store it's data outside of the jail in a place of your choosing
- Mount your custom plex data folder and your media storage dataset inside of the jail
- Create a cron job that updates installed packages every month using the `latest` repository

Note that you still have to apply useful ACL permissions to your media storage dataset for the `plex` user/group. You can use the TrueNAS Core WebUI to do that. Your media storage dataset will be mounted at `/media` inside of the jail. If you don't take care of your permissions, Plex Media Server may not be able to access your media files.

## Installation & Usage
On your TrueNAS Core server, change to a convenient directory, and download the installation script using:
`git clone https://github.com/genxiam/truenas-core-plex-jail.git`

Then simply run the script with root privileges, usage:
`./plex-jail.sh -ph -i 192.168.0.100 -g 192.168.0.1 -d /mnt/tank/plex_data -m /mnt/tank/media`

The following script options are available:
```
-p                      # Use PlexPass package (paid, optional)
-h                      # Use Intel Quick Sync Video hardware (optional)
-i 192.168.0.100        # The IPv4 address of your jail
-g 192.168.0.1          # The default gateway of your jail
-n 24                   # The netmask (defaults to 24, optional)
-d /mnt/tank/plex_data  # Where to store your plex data (database, metadata, etc)
-m /mnt/tank/media      # Where to find your media files (mounted read only)
-j plex                 # The name of your jail (defaults to plex, optional)
```

Note that any additional configuration files, such as `plex-config`, are neither required nor supported any longer.

## Thanks
This script is based on the following projects:
- https://github.com/danb35/freenas-iocage-plex
- https://github.com/kern2011/Freenas-Quicksync
