cd ~
apt-get update
apt-get -fy dist-upgrade
apt-get -fy upgrade
apt-get install -y lsb-release bc

SharedStorageAccountName=$1
SharedAzureFileName=$2
SharedStorageAccountKey=$3

REL=`lsb_release -sc`
DISTRO=`lsb_release -is | tr [:upper:] [:lower:]`
NCORES=` cat /proc/cpuinfo | grep cores | wc -l`
WORKER=`bc -l <<< "4*$NCORES"`

wget http://nginx.org/keys/nginx_signing.key
nginx=stable # use nginx=development for latest development version
apt-key add nginx_signing.key
add-apt-repository -y ppa:nginx/$nginx

apt-get -y update
apt-get -y install nginx

# apt-get install -y -f cifs-utils

apt-get install php-fpm php-mysql -y
apt-get install -fy php-gd
# apt-get --purge autoremove -y
# replace www-data to nginx into /etc/php/7.0/fpm/pool.d/www.conf
# sed -i 's/www-data/nginx/g' /etc/php/7.0/fpm/pool.d/www.conf
service php7.0-fpm restart

mkdir /var/www/html/autoscale

if [[ -z "$SharedStorageAccountName" ]] || [[ -z "$SharedAzureFileName" ]] || [[ -z "$SharedStorageAccountKey" ]]; then
        echo "Cant mount..."
        echo "<?php phpinfo(); ?>" > /var/www/html/autoscale/index.php
else
# mount shared disk
mount -t cifs //$SharedStorageAccountName.file.core.windows.net/$SharedAzureFileName /usr/share/nginx/html -o uid=$(id -u www-data),vers=2.1,username=$SharedStorageAccountName,password=$SharedStorageAccountKey,dir_mode=0770,file_mode=0770
fi

wget https://raw.githubusercontent.com/juliosene/azure-ubuntu-nginx-php-autoscale/master/default

cp  /etc/nginx/sites-enabled/default ~/default-site.bkp

cp default /etc/nginx/sites-enabled/default
