#!/bin/bash

# NOTE: There are many things in this script that need to be changed.
# Search for CHANGE_ME to find them.

# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# set the hostname
echo -n "Enter the hostname from the label and press [ENTER]: "
read name

# set the pw to non-default
echo 'Changing the password for the rock user'
echo "rock:CHANGE_ME" | chpasswd

# setup autologin
if ! grep -q ^autologin-user=rock /etc/lightdm/lightdm.conf; then
  echo 'Setting autologin for the rock user'
  echo 'autologin-user=rock' >> /etc/lightdm/lightdm.conf
fi

# save some ram/processing power
echo 'Disabling bluetooth, cups, saned, and pppd-dns services'
service bluetooth stop > /dev/null 2>&1
service cups stop > /dev/null 2>&1
service pppd-dns stop > /dev/null 2>&1
service saned stop > /dev/null 2>&1
update-rc.d -f bluetooth remove > /dev/null 2>&1
update-rc.d -f cups remove > /dev/null 2>&1
update-rc.d -f saned remove > /dev/null 2>&1
update-rc.d -f pppd-dns remove > /dev/null 2>&1

# setup hosts and hostname
echo 'Setting the hostname'
hostnamectl set-hostname $name
sed -i 's/127.0.1.1.*/127.0.1.1\t'"$name"'/g' /etc/hosts

# turn off the LEDs
echo 'Turning off the front LEDS'
cat << 'EOF' > /usr/local/bin/disable-leds
#!/bin/bash
echo none > /sys/class/leds/blue/trigger
echo none > /sys/class/leds/green/trigger
echo 0 > /sys/class/leds/red/brightness
EOF

chmod 755 /usr/local/bin/disable-leds
/usr/local/bin/disable-leds

if ! grep -q 'leds' /etc/init.d/rc.local; then
  echo -e "\n#disable the radxa leds\n/usr/local/bin/disable-leds" >> /etc/init.d/rc.local
fi

# remove 172.168.1.1 as a nameserver
echo 'Removing bogus nameserver from resolv.conf'
cat /dev/null > /etc/resolvconf/resolv.conf.d/tail
resolvconf -u

# fix network interfaces
i=$((${#name}-1))
host_num=${name:$i:1}

if grep -q 'ac:a2:13:44:a4:ef' /etc/udev/rules.d/70-persistent-net.rules; then
  echo 'Removing bad persistent net rule that Radxa ships'
  cat /dev/null > /etc/udev/rules.d/70-persistent-net.rules
fi

echo 'Configuring network interfaces and removing Network Manager'
cat << EOF > /etc/network/interfaces
# interfaces(5) file used by ifup(8) and ifdown(8)
# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d

auto lo
iface lo inet loopback

auto wlan0
iface wlan0 inet dhcp
        wpa-ssid "CHANGE_ME"
        wpa-psk "CHANGE_ME"
        up route add default gw CHANGE_ME(to a gateway IP) wlan0

auto eth0
allow-hotplug eth0
iface eth0 inet dhcp
        hwaddress ether de:ad:be:ef:12:3$host_num
EOF

apt-get purge network-manager network-manager-gnome network-manager-pptp network-manager-pptp-gnome -y > /dev/null

ifconfig lo up > /dev/null
ifconfig eth0 down > /dev/null
ifconfig wlan0 up > /dev/null
dhclient wlan0 > /dev/null
route add default gw CHANGE_ME(to a gateway IP) wlan0
sleep 5

# The radxa wlan0 udev entry prevents wlan0 from coming up the first time.  Prompt the user to restart
if ! ifconfig wlan0 &> /dev/null; then
  echo 'Network interface wlan0 is not yet up. You need to reboot before running this script again. Hit ENTER key to exit'
  read
  exit
fi

# make sure the user resized the partition and resize the filesystem
if ! df -h | grep -q 15G; then
  echo 'Resizing the root file system. This will take a while.'
  resize2fs /dev/mmcblk0p1 &> /dev/null
  if ! df -h | grep -q 15G; then
    echo "Root partition is less than 15G and couldn't be resized.  Did you forget to fix the partition table and reboot?  Hit ENTER to exit"
    read
    exit
  fi
fi

apt-get install ethtool net-tools -y > /dev/null

echo 'Placing ntpdate workaround script for RADXAs without batteries'
cat << 'EOF' > /etc/init.d/time_fix
#!/bin/sh
### BEGIN INIT INFO
# Provides:          time_fix
# X-Start-Before:    openvpn ntp
# Default-Start:     2 3 4 5
### END INIT INFO

ntpdate ntp.ubuntu.com
EOF
update-rc.d time_fix defaults 10

echo 'Installing NTP and syncing time with the Ubuntu time server'
ntpdate ntp.ubuntu.com
apt-get install ntp -y > /dev/null

# upgrade to the latest software
echo 'Performing package upgrade'
apt-get update > /dev/null
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -f dist-upgrade > /dev/null

echo 'Installing full vim'
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -f install vim

# Autostart Firefox
echo 'Setting Firefox to start at boot'
apt-get install firefox -y > /dev/null 2>&1
mkdir ~/.config/autostart/ > /dev/null 2>&1
cat << EOF > /home/rock/.config/autostart/firefox.desktop
[Desktop Entry]
Type=Application
Exec=firefox 'http://www.therealtimsmith.com'
EOF

# install / setup a vnc server
echo 'Installing and configuring X11vnc'
apt-get install x11vnc -y > /dev/null
mkdir /home/rock/.vnc > /dev/null 2>&1
cat << 'EOF' > /etc/init.d/x11vnc
#! /bin/sh
#
### BEGIN INIT INFO
# Provides: x11vnc
# Required-Start: $syslog $local_fs
# Required-Stop: $syslog $local_fs
# Should-Start: LightDM
# Default-Start: 2
# Default-Stop: 1
# Short-Description: x11 vnc
# Description: x11vnc
### END INIT INFO
DAEMON=/usr/bin/x11vnc
NAME=x11vnc
DESC="X11 vnc"
test -x $DAEMON || exit 0
DAEMON_OPTS="-rfbport 5900 -auth /var/run/lightdm/root/:0 -passwd CHANGE_ME -nomodtweak -noxrecord -shared -forever -o /var/log/x11vnc.log -bg"
set -e
 case "$1" in
           start)
                   echo -n "Starting $DESC: "
                   start-stop-daemon --start --quiet --pidfile /var/run/$NAME.pid \
                                                     --exec $DAEMON -- $DAEMON_OPTS &
                   echo "$NAME."
           ;;
           stop)
                   echo -n "Stopping $DESC: "
                   start-stop-daemon --stop --oknodo --quiet --pidfile /var/run/$NAME.pid \
                                                    --exec $DAEMON
                   echo "$NAME."
           ;;
           restart)
                      echo -n "Restarting $DESC: "
                      start-stop-daemon --stop --quiet --pidfile \
                      /var/run/$NAME.pid --exec $DAEMON
                      sleep 1
                      start-stop-daemon --start --quiet --pidfile \
                      /var/run/$NAME.pid --exec $DAEMON -- $DAEMON_OPTS
                      echo "$NAME."
          ;;
          status)
                     if [ -s /var/run/$NAME.pid ]; then
                        RUNNING=$(cat /var/run/$NAME.pid)
                        if [ -d /proc/$RUNNING ]; then
                            if [ $(readlink /proc/$RUNNING/exe) = $DAEMON ]; then
                                echo "$NAME is running."
                                exit 0
                            fi
                        fi
                        # No such PID, or executables don't match
                        echo "$NAME is not running, but pidfile existed."
                        rm /var/run/$NAME.pid
                        exit 1
                     else
                           rm -f /var/run/$NAME.pid
                           echo "$NAME not running."
                           exit 1
                     fi
          ;;
          *)
            N=/etc/init.d/$NAME
            echo "Usage: $N {start|stop|restart|force-reload}" >&2
            exit 1
           ;;
 esac
exit 0
EOF

chmod 755 /etc/init.d/x11vnc
service x11vnc start > /dev/null
update-rc.d x11vnc defaults 80 20 > /dev/null 2>&1

# install openvpn
echo 'Installing OpenVPN client'
apt-get install openvpn -y > /dev/null
cat << 'EOF' > /etc/openvpn/client.conf
client
dev tun
proto udp
remote CHANGE_ME 1194
resolv-retry infinite
keepalive 10 120
nobind
persist-key
persist-tun
ca ca.crt
cert client.crt
key client.key
ns-cert-type server
comp-lzo
verb 3
up /etc/openvpn/update-resolv-conf
down /etc/openvpn/update-resolv-conf
EOF

# startup openvpn
echo 'Starting up OpenVPN and waiting 20 seconds for the interface to come up'
service openvpn restart
sleep 20

# make sure the OpenVPN tunnel interface is up before breaking name resolution on the host
while ! ifconfig tun0 &> /dev/null; do
  echo 'The OpenVPN tunnel interface tun0 does not appear to be up. Fix that and hit enter to try again'
  read
done

echo 'Make resolveconf work better with OpenVPN'
cat << 'EOF' > /etc/resolvconf/resolv.conf.d/head
options timeout:5
options attempts:2
EOF
resolvconf -u

echo 'Setup complete. You will need to reboot now for networking changes to take affect'
