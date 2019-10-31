#!/bin/bash
# move away or delete distribution defaults
mkdir -p /build
mkdir -p /build/conf/dist
mkdir -p /build/conf/slapd.d/base
rm -rf /var/lib/openldap/openldap-data
mv /etc/openldap/slapd.conf /build/conf/dist/slapd.conf
mv /etc/openldap/DB_CONFIG.example /build/conf/dist/DB_CONFIG.example
mv /etc/openldap/ldap.conf /build/conf/dist/ldap.conf
mv /etc/openldap/slapd.ldif /build/conf/dist/slapd.ldif
mv -f /etc/openldap/schema /build/conf/dist/schema

apk --update add tzdata
cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime
echo "Europe/Berlin" > /etc/timezone

rm /build.sh