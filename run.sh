#!/bin/bash

# 1. Enter the public ip of this instance
echo "## Enter the public ip of this instance："
read public_ip

# Print the public_ip
echo "The public ip is：$public_ip"

# 2. Install StrongSwan
echo "## Installing StrongSwan..."
sudo apt update
sudo apt install strongswan strongswan-pki libcharon-extra-plugins libcharon-extauth-plugins libstrongswan-extra-plugins libtss2-tcti-tabrmd0 -y

# 3. Create four .pem files and copy to /etc/ipsec.d/
echo "## Creating four .pem files..."
mkdir -p ~/pki/cacerts ~/pki/certs ~/pki/private
chmod 700 ~/pki
pki --gen --type rsa --size 4096 --outform pem > ~/pki/private/ca-key.pem
pki --self --ca --lifetime 3650 --in ~/pki/private/ca-key.pem \
            --type rsa --dn "CN=ohio" --outform pem > ~/pki/cacerts/ca-cert.pem
pki --gen --type rsa --size 4096 --outform pem > ~/pki/private/server-key.pem

#  Set public ip name below
pki --pub --in ~/pki/private/server-key.pem --type rsa \
        | pki --issue --lifetime 1825 \
                --cacert ~/pki/cacerts/ca-cert.pem \
                --cakey ~/pki/private/ca-key.pem \
                --dn "CN=$public_ip" --san $public_ip --san @$public_ip \
                --flag serverAuth --flag ikeIntermediate --outform pem \
        >  ~/pki/certs/server-cert.pem

echo "## Copying .pem files to /etc/ipsec.d/..."
sudo cp -r ~/pki/* /etc/ipsec.d/
sudo mv /etc/ipsec.conf /etc/ipsec.conf.original

# 4. Set /etc/ipsec.conf config file for connection
echo "## Setting up /etc/ipsec.conf config file..."
sudo sh -c 'cat >> /etc/ipsec.conf << EOF
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
        leftid=$public_ip
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
EOF'

echo "ipsec.conf config settings written successfully."
