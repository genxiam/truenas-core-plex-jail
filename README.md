# truenas-core-scripts
Scripted installations of Plex Media Server, SABnzbd and Transmission in TrueNAS Core 13.1-RELEASE jails

## Get the scripts
On your TrueNAS Core server change to a convenient directory and download the installation scripts using git:  
`git clone https://github.com/genxiam/truenas-core-scripts.git`

## Description: `install_plex.sh`
This script will:
- Try to enable Intel Quick Sync Video support i.e. enable hardware transcoding (results may vary)
- Create a `plex` jail and install Plex Media Server into it (with or without PlexPass)
- Create the `plex` user and group on the host system (needed for your dataset ACLs)
- Configure Plex Media Server to store it's data outside of the jail in a place of your choosing
- Mount your custom plex data folder and your media storage dataset inside of the jail
- Create a cron job that updates installed packages every month using the `latest` repository

## Usage: `install_plex.sh`
Simply run the following script with root privileges, usage:  
`./install_plex.sh -ph -i 192.168.0.100 -g 192.168.0.1 -d /mnt/tank/plex_data -m /mnt/tank/media`

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

## Description: `install_sabnzbd.sh`
This script will:
- Create a `sabnzbd` jail and install SABnzbd into it
- Create the `sabnzbd` user and group on the host system (needed for your dataset ACLs)
- Mount your custom data storage dataset inside of the jail at `/media`
- Create a cron job that updates installed packages every month using the `latest` repository

## Usage: `install_sabnzbd.sh`
Simply run the following script with root privileges, usage:  
`./install_sabnzbd.sh -i 192.168.0.110 -g 192.168.0.1 -d /mnt/tank/usenet`

The following script options are available:
```
-i 192.168.0.110        # The IPv4 address of your jail
-g 192.168.0.1          # The default gateway of your jail
-n 24                   # The netmask (defaults to 24, optional)
-d /mnt/tank/usenet     # Where to store your downloads
-j sabnzbd              # The name of your jail (defaults to sabnzbd, optional)
```

## Description: `install_transmission.sh`
This script will:
- Create a `transmission` jail and install Transmission into it
- Create the `transmission` user and group on the host system (needed for your dataset ACLs)
- Mount your custom data storage dataset inside of the jail at `/media`
- Create a cron job that updates installed packages every month using the `latest` repository

## Usage: `install_transmission.sh`
Simply run the following script with root privileges, usage:  
`./install_transmission.sh -i 192.168.0.120 -g 192.168.0.1 -d /mnt/tank/torrents`

The following script options are available:
```
-i 192.168.0.120        # The IPv4 address of your jail
-g 192.168.0.1          # The default gateway of your jail
-n 24                   # The netmask (defaults to 24, optional)
-d /mnt/tank/torrents   # Where to store your downloads
-j transmission         # The name of your jail (defaults to transmission, optional)
```

## About permissions
You still have to manually apply useful ACL permissions to your data storage datasets for the `plex`, `sabnzbd` and `transmission` users/groups. You can use the TrueNAS Core WebUI to do that. Your data storage datasets will be mounted at `/media` inside of the jails. If you don't take care of your permissions, you may not be able to access your data properly.

## Thanks
The plex script is based on the following projects:
- https://github.com/danb35/freenas-iocage-plex
- https://github.com/kern2011/Freenas-Quicksync
