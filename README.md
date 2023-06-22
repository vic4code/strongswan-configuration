# Strongswan vpn serving configuration
> Establish a IPSec StrongSwan vpn service on Ubuntu 20.04. Just enter the `public ip` of the instance and the `name` of the service, then the configursation files will be generated.
## Quick Start
```
bash run.sh
```
- Bingo!!

# Step by step confuguration

## Set Up IPSec StrongSwan on Ubuntu 20.04
- [Reference 1](https://www.digitalocean.com/community/tutorials/how-to-set-up-an-ikev2-vpn-server-with-strongswan-on-ubuntu-20-04)
- [Reference 2](https://linuxopsys.com/topics/install-and-configure-strongswan-vpn-on-ubuntu)
- [Reference 3](https://bluegrid.io/setting-up-a-vpn-server-with-strongswan-on-ubuntu-20-04/)
### 1. Install StrongSwan
```bash
sudo apt update
sudo apt install strongswan strongswan-pki libcharon-extra-plugins libcharon-extauth-plugins libstrongswan-extra-plugins libtss2-tcti-tabrmd0 -y
```

### 2. Create four`.pem` files and copy to ``/etc/ipsec.d/``:

```bash
# Create files under ~ 
mkdir -p ~/pki/{cacerts,certs,private}
chmod 700 ~/pki
pki --gen --type rsa --size 4096 --outform pem > ~/pki/private/ca-key.pem
pki --self --ca --lifetime 3650 --in ~/pki/private/ca-key.pem \
    --type rsa --dn "CN=VPN" --outform pem > ~/pki/cacerts/ca-cert.pem
pki --gen --type rsa --size 4096 --outform pem > ~/pki/private/server-key.pem

# Choose to set by (1)public ip or (2)dns name below
pki --pub --in ~/pki/private/server-key.pem --type rsa \
    | pki --issue --lifetime 1825 \
        --cacert ~/pki/cacerts/ca-cert.pem \
        --cakey ~/pki/private/ca-key.pem \
        --dn "CN=15.164.244.212" --san 15.164.244.212 --san @15.164.244.212 \
        --flag serverAuth --flag ikeIntermediate --outform pem \
    >  ~/pki/certs/server-cert.pem

# copy and rename files
sudo cp -r ~/pki/* /etc/ipsec.d/
sudo mv /etc/ipsec.conf{,.original}
```


#### (1) `server-cert.pem` `--dn` and `--san` by dns (not working, not sure if domain needs to be enabled)
```bash
pki --pub --in ~/pki/private/server-key.pem --type rsa \
    | pki --issue --lifetime 1825 \
        --cacert ~/pki/cacerts/ca-cert.pem \
        --cakey ~/pki/private/ca-key.pem \
        --dn "CN=magicisnevergone.com" --san magicisnevergone.com --san @magicisnevergone.com \
        --flag serverAuth --flag ikeIntermediate --outform pem \
    >  ~/pki/certs/server-cert.pem
```

#### (2) `server-cert.pem` `--dn` and `--san` by public ip 
```bash
pki --pub --in ~/pki/private/server-key.pem --type rsa \
    | pki --issue --lifetime 1825 \
        --cacert ~/pki/cacerts/ca-cert.pem \
        --cakey ~/pki/private/ca-key.pem \
        --dn "CN=15.164.244.212" --san 15.164.244.212 --san @15.164.244.212 \
        --flag serverAuth --flag ikeIntermediate --outform pem \
    >  ~/pki/certs/server-cert.pem
```
### 3. Set `/etc/ipsec.conf` config file for connection:
the left side by convention refers to the local system that you are configuring, in this case the server. The right side directives in these settings will refer to remote clients, like phones and other computers.
```bash
sudo vi /etc/ipsec.conf
```
```bash
config setup
      charondebug="ike 2, knl 2, cfg 2, net 2, esp 2, dmn 2, mgr 2"
      strictcrlpolicy=no
      uniqueids=yes
      cachecrls=no

conn ipsec-ikev2-vpn
      auto=add
      compress=no
      type=tunnel
      keyexchange=ikev2
      fragmentation=yes
      forceencaps=yes
      dpdaction=clear
      dpddelay=300s
      rekey=no
      left=%any
      leftid=15.164.244.212 #or @domain.com
      leftcert=server-cert.pem
      leftsendcert=always 
      leftsubnet=0.0.0.0/0
      right=%any
      rightid=%any
      rightauth=eap-mschapv2
      rightsourceip=10.10.10.0/24
      rightdns=8.8.8.8,8.8.4.4
      rightsendcert=never
      eap_identity=%identity
      
      # Why is this not neccessary sometimes??
      ike=chacha20poly1305-sha512-curve25519-prfsha512,aes256gcm16-sha384-prfsha384-ecp384,aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024!
      esp=chacha20poly1305-sha512,aes256gcm16-ecp384,aes256-sha256,aes256-sha1,3des-sha1!
```

### 4. Set `.secretes` to assign usernames
```bash
sudo vi /etc/ipsec.secrets
```
-  In `/etc/ipsec.secrets`, define users and password as below:
```bash
: RSA "server-key.pem"
admin : EAP "admin"
user : EAP "user"
...
```

### 5. Configure the Firewall & Kernel IP Forwarding
```
sudo ufw allow OpenSSH
sudo ufw enable
sudo ufw allow 500,4500/udp
ip route show default
```
- Set `/etc/ufw/before.rules` to open **Firewall**:
```bash
sudo vi /etc/ufw/before.rules
```
- Add `*nat`  and `*mangle` in the beginning of the file:
```bash
*nat
-A POSTROUTING -s 10.10.10.0/24 -o eth0 -m policy --pol ipsec --dir out -j ACCEPT
-A POSTROUTING -s 10.10.10.0/24 -o eth0 -j MASQUERADE
COMMIT

*mangle
-A FORWARD --match policy --pol ipsec --dir in -s 10.10.10.0/24 -o eth0 -p tcp -m tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1361:1536 -j TCPMSS --set-mss 1360
COMMIT

*filter
:ufw-before-input - [0:0]
:ufw-before-output - [0:0]
:ufw-before-forward - [0:0]
:ufw-not-local - [0:0]
. . .
```
- Next, after the *filter and chain definition lines, add one more block of configuration:
```bash
. . .
*filter
:ufw-before-input - [0:0]
:ufw-before-output - [0:0]
:ufw-before-forward - [0:0]
:ufw-not-local - [0:0]

-A ufw-before-forward --match policy --pol ipsec --dir in --proto esp -s 10.10.10.0/24 -j ACCEPT
-A ufw-before-forward --match policy --pol ipsec --dir out --proto esp -d 10.10.10.0/24 -j ACCEPT
```
- Set `/etc/ufw/sysctl.conf` for **IP Forwarding**:
```bash
sudo vi /etc/ufw/sysctl.conf
```
- Uncomment the following rules:
```bash
net/ipv4/ip_forward=1
```
- add the following 2 lines at the end of the file:
```bash
net/ipv4/conf/all/accept_redirects=0
net/ipv4/conf/all/send_redirects=0
net/ipv4/ip_no_pmtu_disc=1
```
- Enable Kernel Packet Forwarding
```bash
sudo vi /etc/sysctl.conf
```
- Uncomment the following lines:
```
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
```
- reload the settings
```
sudo sysctl -p
```
- Finally:
```bash
sudo ufw disable
sudo ufw enable
```

### 6. Start strongswan serving and check the status:
```
sudo systemctl restart strongswan-starter
sudo systemctl enable strongswan-starter
sudo systemctl status strongswan-starter
```
- Successful messeage:
```bash
● strongswan-starter.service - strongSwan IPsec IKEv1/IKEv2 daemon using ipsec.conf
     Loaded: loaded (/lib/systemd/system/strongswan-starter.service; enabled; vendor preset: enabled)
     Active: active (running) since Sat 2023-03-11 05:33:05 UTC; 56min ago
   Main PID: 91351 (starter)
      Tasks: 18 (limit: 560)
     Memory: 7.5M
     CGroup: /system.slice/strongswan-starter.service
             ├─91351 /usr/lib/ipsec/starter --daemon charon --nofork
             └─91366 /usr/lib/ipsec/charon --debug-ike 2 --debug-knl 2 --debug-cfg 2 --debug-net 2 --debug-esp 2 --debug-dmn 2 --debug-mgr 2

Mar 11 06:28:46 ip-172-26-6-28 charon[91366]: 04[NET] sending packet: from 172.26.6.28[4500] to 118.165.58.212[4500]
Mar 11 06:28:46 ip-172-26-6-28 charon[91366]: 11[MGR] checkin IKE_SA ipsec-ikev2-vpn[20]
Mar 11 06:28:46 ip-172-26-6-28 charon[91366]: 11[MGR] checkin of IKE_SA successful
Mar 11 06:29:05 ip-172-26-6-28 charon[91366]: 12[MGR] checkout IKEv2 SA with SPIs 8f68b54742689db7_i 2df48b0ba3bfcf91_r
Mar 11 06:29:05 ip-172-26-6-28 charon[91366]: 12[MGR] IKE_SA checkout not successful
Mar 11 06:29:06 ip-172-26-6-28 charon[91366]: 14[MGR] checkout IKEv2 SA with SPIs 8f68b54742689db7_i dbdc5a36bb8220df_r
Mar 11 06:29:06 ip-172-26-6-28 charon[91366]: 14[MGR] IKE_SA ipsec-ikev2-vpn[20] successfully checked out
Mar 11 06:29:06 ip-172-26-6-28 charon[91366]: 14[KNL] querying policy 0.0.0.0/0 === 10.10.10.1/32 out
Mar 11 06:29:06 ip-172-26-6-28 charon[91366]: 14[MGR] checkin IKE_SA ipsec-ikev2-vpn[20]
Mar 11 06:29:06 ip-172-26-6-28 charon[91366]: 14[MGR] checkin of IKE_SA successful
```

### 7. Prepare `ca-cert.pem` for local macos or ios:
- `sudo vi ca-cert.pem` at local and copy the content from `cat` to the created `.pem`:
```
cat /etc/ipsec.d/cacerts/ca-cert.pem
```
- Connecting from iOS:

To configure the VPN connection on an iOS device, follow these steps:

>1. Send yourself an email with the root certificate attached. 
>2. Open the email on your iOS device and tap on the attached certificate file, then tap Install and enter your passcode. Once it installs, tap Done.
>3. Go to Settings, General, VPN and tap Add VPN Configuration. This will bring up the VPN connection configuration screen.
>4. Tap on Type and select IKEv2.
In the Description field, enter a short name for the VPN connection. This could be anything you like.
>5. In the Server and Remote ID field, enter the server’s domain name or IP address. The Local ID field can be left blank.
>6. Enter your username and password in the Authentication section, then tap Done.
>7. Select the VPN connection that you just created, tap the switch on the top of the page, and you’ll be connected.

### 8. Check the connection by `ipsec status` in the instance:
```
sudo ipsec status
sudo watch ipsec status
sudo watch ipsec statusall #check username as well
```

### 9. Speed test on ubuntu
- Install `speedtest-cli`
```bash
sudo apt install speedtest-cli
speedtest-cli
```

### Other useful commands:
- Check the system log
```
tail /var/log/syslog -f
```
- Check dns server
```
nslookup magicisnevergone.example.com
```
- Clear dns cached
```
sudo systemd-resolve --flush-caches
```
- Check dns resolving status
```
resolvectl status
sudo systemctl restart systemd-resolved
sudo systemctl restart systemd-resolved.service
```
- [`system-resolved` 設定](https://officeguide.cc/linux-systemd-resolved-local-name-resolution-configuration-tutorial/)
    - `/etc/resolv.conf`
    - `/etc/systemd/resolved.conf`
    - `/etc/hosts`
- Check vpn connection port:
```bash
(base) victor@Victors-MacBook-Air ~ % netstat -an | grep 15.164.244.212
tcp4       0      0  172.20.10.11.59003     15.164.244.212.22      ESTABLISHED
udp4       0      0  172.20.10.11.4500      15.164.244.212.4500
udp4       0      0  172.20.10.11.500       15.164.244.212.500
```
- Check strongswan version
```
$ ipsec --versioncode
U5.8.2/K5.4.0-1018-aws
```

### Advanced settings
- [stronswan configuration files](https://wiki.strongswan.org/projects/strongswan/wiki/ConfigurationFiles)
- [Migration from ipsec.conf to swanctl.conf](https://wiki.strongswan.org/projects/strongswan/wiki/Fromipsecconf)
- [ipsec.conf](https://wiki.strongswan.org/projects/strongswan/wiki/ConnSection)

### Inspection of ipesec
```
sudo watch systemctl status strongswan-starter
sudo watch ipsec statusall
sudo systemctl restart strongswan-starter
```
