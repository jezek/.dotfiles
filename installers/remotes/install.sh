exit
#TODO ip detection & try ssh to all ips (find out which are my devices) & mount/remount all devices

IPs=sudo arp-scan --localnet --numeric --quiet --ignoredups | grep -E '([a-f0-9]{2}:){5}[a-f0-9]{2}' | awk '{print $1}'
