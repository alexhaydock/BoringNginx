#!/bin/bash
set -u
if [ "$(id -u)" -eq 0 ]; then echo -e "This script is not intended to be run as root.\nExiting." && exit 1; fi


## Note to self. (For use when generating patches).
# diff -ur nginx-1.11.3/ nginx-1.11.3-patched/ > ../boring.patch


ngxver="1.11.3" # Target nginx version
bdir="/tmp/boringnginx-$RANDOM" # Set build directory


# Handle arguments passed to the script. Currently only accepts the flag to
# include passenger at compile time,but I might add a help section or more options soon.
PASSENGER=0
while [ "$#" -gt 0 ]; do
	case $1 in
		--passenger|-passenger|passenger) PASSENGER="1"; shift 1;;
		*) echo "Invalid argument: $1" && exit 10;;
	esac
done


# Prompt our user before we start removing stuff
CONFIRMED=0
echo -e "This script will remove any versions of Nginx you installed using apt, and\nreplace any version of Nginx built with a previous version of this script."
while true
do
	echo ""
	read -p "Do you wish to continue? (Y/N)" answer
	case $answer in
		[yY]* )
			CONFIRMED=1
			break;;

		* )
			echo "Please enter 'Y' to continue or use ^C to exit.";;
	esac
done
if [ "$CONFIRMED" -eq 0 ]; then echo -e "Something went wrong.\nExiting." && exit 1; fi


# Install deps & remove old nginx if we installed it with apt
sudo systemctl stop nginx
sudo systemctl disable nginx
sudo apt remove nginx nginx-common nginx-full nginx-light
sudo apt install build-essential cmake git golang libpcre3-dev wget zlib1g-dev libcurl4-openssl-dev


# Build BoringSSL
git clone https://boringssl.googlesource.com/boringssl "$bdir/boringssl"
cd "$bdir/boringssl"
mkdir build && cd build
cmake ../
make


# Make an .openssl directory for nginx and then symlink BoringSSL's include directory tree
mkdir -p "$bdir/boringssl/.openssl/lib"
cd "$bdir/boringssl/.openssl"
ln -s ../include


# Copy the BoringSSL crypto libraries to .openssl/lib so nginx can find them
cd "$bdir/boringssl"
cp "build/crypto/libcrypto.a" "build/ssl/libssl.a" ".openssl/lib"


# Download "ngx_headers_more" module for finer-grained control over server headers
git clone https://github.com/openresty/headers-more-nginx-module.git "$bdir/ngx_headers_more"


# Download and prepare nginx
cd "$bdir"
wget --https-only "https://nginx.org/download/nginx-$ngxver.tar.gz"
wget "https://github.com/ajhaydock/BoringNginx/raw/master/$ngxver/src/boring.patch"
if [ -f "nginx-$ngxver.tar.gz" ]; then tar zxvf "nginx-$ngxver.tar.gz"; else echo -e "\nFailed to download nginx $ngxver" && exit 2; fi
cd "$bdir/nginx-$ngxver"


# Config nginx based on the flags passed to the script, if any
EXTRACONFIG=""
WITHROOT=""
if [ $PASSENGER -eq 1 ]
then
	echo "" && echo "Phusion Passenger module enabled."
	sudo gem install rails
	sudo gem install passenger
	EXTRACONFIG="$EXTRACONFIG --add-module=$(passenger-config --root)/src/nginx_module"
	WITHROOT="sudo " # Passenger needs root to read/write to /var/lib/gems
fi


# Run the config with default options and append any additional options specified by the above section
$WITHROOT./configure --prefix=/usr/share/nginx \
	--sbin-path=/usr/sbin/nginx \
	--conf-path=/etc/nginx/nginx.conf \
	--error-log-path=/var/log/nginx/error.log \
	--http-log-path=/var/log/nginx/access.log \
        --pid-path=/run/nginx.pid \
        --lock-path=/run/lock/subsys/nginx \
        --user=www-data \
        --group=www-data \
        --with-threads \
        --with-file-aio \
        --with-ipv6 \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_realip_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_slice_module \
        --with-http_stub_status_module \
        --without-select_module \
        --without-poll_module \
        --without-mail_pop3_module \
        --without-mail_imap_module \
        --without-mail_smtp_module \
	--add-module="$bdir/ngx_headers_more" \
	--with-openssl="$bdir/boringssl" \
	--with-cc-opt="-g -O2 -fPIE -fstack-protector-all -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security -I ../boringssl/.openssl/include/" \
	--with-ld-opt="-Wl,-Bsymbolic-functions -Wl,-z,relro -L ../boringssl/.openssl/lib" \
	$EXTRACONFIG


# Fix "Error 127" during build
touch "$bdir/boringssl/.openssl/include/openssl/ssl.h"


# Fix some other build errors caused by nginx expecting OpenSSL
patch -p1 < "../boring.patch"


# Build nginx
make # Fortunately we can get away without root here, even for Passenger installs
sudo make install


# Add systemd service
cd "$bdir/"
wget "https://github.com/ajhaydock/BoringNginx/raw/master/$ngxver/src/nginx.service"
sudo cp -f -v nginx.service "/lib/systemd/system/nginx.service"

# Enable & start service
sudo systemctl enable nginx.service
sudo systemctl start nginx.service

# Finish script
echo ""
sudo /usr/sbin/nginx -V
echo ""
sudo ldd /usr/sbin/nginx

# If you previously installed nginx via apt and get errors when trying to boot this compiled version, you might need to remove /etc/nginx and then try the buildscript again (or just the 'make install' part)
