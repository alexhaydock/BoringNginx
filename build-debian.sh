#!/bin/bash
set -u

ngxver="1.10.0" # Current nginx version
bdir="/tmp/boringnginx-$RANDOM" # Set build directory


## For use when generating patches
# diff -ur nginx-1.10.0/ nginx-1.10.0-patched/ > ../boring.patch


# Install deps & remove old nginx if we installed it with apt
sudo systemctl stop nginx
sudo systemctl disable nginx
sudo apt purge nginx
sudo apt install build-essential cmake git golang libpcre3-dev wget


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


# Config nginx
cd "$bdir"
wget "http://nginx.org/download/nginx-$ngxver.tar.gz"
wget "https://github.com/ajhaydock/BoringNginx/raw/master/boring.patch"
tar zxvf "nginx-$ngxver.tar.gz"
cd "$bdir/nginx-$ngxver"
./configure \
	--prefix=/usr/share/nginx \
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
	--with-openssl="$bdir/boringssl" \
	--with-cc-opt="-g -O2 -fPIE -fstack-protector-all -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security -I ../boringssl/.openssl/include/" \
	--with-ld-opt="-Wl,-Bsymbolic-functions -Wl,-z,relro -L ../boringssl/.openssl/lib"


# Fix "Error 127" during build
touch "$bdir/boringssl/.openssl/include/openssl/ssl.h"


# Fix some other build errors caused by nginx expecting OpenSSL
patch -p1 < "../boring.patch"


# Build nginx
make
sudo make install


# Add systemd service
cd "$bdir/"
wget "https://github.com/ajhaydock/BoringNginx/raw/master/nginx.service"
cp -f -v nginx.service "/lib/systemd/system/nginx.service"

echo ""
sudo /usr/sbin/nginx -V
echo ""
sudo ldd /usr/sbin/nginx

# If you previously installed nginx via apt and get errors when trying to boot this compiled version, you might need to remove /etc/nginx and then try the buildscript again (or just the 'make install' part)
