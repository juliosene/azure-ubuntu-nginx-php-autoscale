#!/bin/bash
# Install Nginx + php-fpm + apc cache for Ubuntu and Debian distributions
cd ~
# apt-get update
# apt-get -fy dist-upgrade
# apt-get -fy upgrade
apt-get install lsb-release bc
REL=`lsb_release -sc`
DISTRO=`lsb_release -is | tr [:upper:] [:lower:]`
NCORES=` cat /proc/cpuinfo | grep cores | wc -l`
WORKER=`bc -l <<< "4*$NCORES"`

OPTION=${1-2}
SharedStorageAccountName=$2
SharedAzureFileName=$3
SharedStorageAccountKey=$4
PHPVersion=${5-5}
InstallTools=${6:-"no"}
ToolsUser=$7
ToolsPass=$8

wget http://nginx.org/keys/nginx_signing.key
apt-key add nginx_signing.key
add-apt-repository "deb http://nginx.org/packages/$DISTRO $REL nginx"
# add-apt-repository "deb-src http://nginx.org/packages/$DISTRO $REL nginx"
if [ "$PHPVersion" -eq 7 ]; then
apt-get install -fy python-software-properties
LC_ALL=en_US.UTF-8 add-apt-repository ppa:ondrej/php -y
fi

apt-get -y update

apt-get install -y -f cifs-utils

# Create Azure file shere if is the first VM
if [ $OPTION -lt 1 ]; 
then  
# Create Azure file share that will be used by front end VM's for moodledata directory
wget https://raw.githubusercontent.com/juliosene/azure-nginx-php-mariadb-cluster/master/create-file-share.sh
bash create-file-share.sh $SharedStorageAccountName $SharedAzureFileName $SharedStorageAccountKey > /root/create-file-share.log

fi

apt-get install -fy nginx
# # PHP 7
if [ "$PHPVersion" -eq 7 ]; then
apt-get install php7.0 php7.0-fpm php7.0-mysql -y
apt-get install -fy php-apc php7.0-gd
apt-get --purge autoremove -y
# replace www-data to nginx into /etc/php/7.0/fpm/pool.d/www.conf
sed -i 's/www-data/nginx/g' /etc/php/7.0/fpm/pool.d/www.conf
service php7.0-fpm restart
# # PHP 5
else
apt-get install -fy php5-fpm php5-cli php5-mysql
apt-get install -fy php-apc php5-gd
# replace www-data to nginx into /etc/php5/fpm/pool.d/www.conf
sed -i 's/www-data/nginx/g' /etc/php5/fpm/pool.d/www.conf
service php5-fpm restart
fi

# backup default Nginx configuration
mkdir /etc/nginx/conf-bkp
cp /etc/nginx/conf.d/default.conf /etc/nginx/conf-bkp/default.conf
cp /etc/nginx/nginx.conf /etc/nginx/nginx-conf.old
#
# Replace nginx.conf
#
wget https://raw.githubusercontent.com/juliosene/azure-nginx-php-mariadb-cluster/master/files/nginx.conf

sed -i "s/#WORKER#/$WORKER/g" nginx.conf
mv nginx.conf /etc/nginx/

# replace Nginx default.conf
#
wget https://raw.githubusercontent.com/juliosene/azure-nginx-php-mariadb-cluster/master/files/default.conf

# replace for php7 sock
if [ "$PHPVersion" -eq 7 ]; then
sed -i "s,/var/run/php5-fpm.sock,/var/run/php/php7.0-fpm.sock,g" default.conf
fi

#sed -i "s/#WORKER#/$WORKER/g" nginx.conf
mv default.conf /etc/nginx/conf.d/

# Memcache client installation
# ## php 7
if [ "$PHPVersion" -eq 7 ]; then
apt-get install -fy php-memcached
# wget https://raw.githubusercontent.com/juliosene/azure-nginx-php-mariadb-cluster/master/files/memcache.ini
# mv memcache.ini /etc/php/mods-available/
# ln -s /etc/php/mods-available/memcache.ini  /etc/php/7.0/fpm/conf.d/20-memcache.ini
# ## php 5
else
apt-get install -fy php-pear
apt-get install -fy php5-dev
printf "\n" |pecl install -f memcache
wget https://raw.githubusercontent.com/juliosene/azure-nginx-php-mariadb-cluster/master/files/memcache.ini
#sed -i "s/#WORKER#/$WORKER/g" memcache.ini
mv memcache.ini /etc/php5/mods-available/
ln -s /etc/php5/mods-available/memcache.ini  /etc/php5/fpm/conf.d/20-memcache.ini
fi
#
# mount share file on /usr/share/nginx/html

# azure storage share list $SharedAzureFileName -a $SharedStorageAccountName -k $SharedStorageAccountKey |grep -q 'html' && echo 'yes'
mount -t cifs //$SharedStorageAccountName.file.core.windows.net/$SharedAzureFileName /usr/share/nginx/html -o uid=$(id -u nginx),vers=2.1,username=$SharedStorageAccountName,password=$SharedStorageAccountKey,dir_mode=0770,file_mode=0770

#add mount to /etc/fstab to persist across reboots
chmod 770 /etc/fstab
echo "//$SharedStorageAccountName.file.core.windows.net/$SharedAzureFileName /usr/share/nginx/html cifs uid=$(id -u nginx),vers=3.0,username=$SharedStorageAccountName,password=$SharedStorageAccountKey,dir_mode=0770,file_mode=0770" >> /etc/fstab

if [ $OPTION -lt 1 ]; 
then  
#
# Edit default page to show php info
#
#mv /usr/share/nginx/html/index.html /usr/share/nginx/html/index.php
mkdir /usr/share/nginx/html/web
echo -e "<html><title>Azure Nginx PHP</title><body><h2 align='center'>Your Nginx and PHP are running!</h2><h2 align='center'>Host: <?= gethostname() ?></h2></br>\n<?php\nphpinfo();\n?></body>" > /usr/share/nginx/html/web/index.php
#
#
# Install admin tools
if [ $InstallTools == "yes" ];
then
   wget https://raw.githubusercontent.com/juliosene/azure-nginx-php-mariadb-cluster/master/tools/install-tools.sh
   bash install-tools.sh $ToolsUser $ToolsPass
fi

fi

if [ $InstallTools == "yes" ];
then
if [ $OPTION -gt 0 ]; 
then  
wget https://raw.githubusercontent.com/juliosene/azure-nginx-php-mariadb-cluster/master/tools/tools.conf
mv tools.conf /etc/nginx/conf.d/
fi
fi

#
# Services restart
#
if [ "$PHPVersion" -eq 7 ]; then
sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 100M/g" /etc/php/7.0/fpm/php.ini
service php7.0-fpm restart
else
sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 100M/g" /etc/php5/fpm/php.ini
service php5-fpm restart
fi

service nginx restart
