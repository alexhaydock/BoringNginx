#!/bin/bash
set -u
if [ "$(id -u)" -eq 0 ]; then echo -e "This script is not intended to be run as root.\nExiting." && exit 1; fi

LATESTNGINX="1.12.0" # Set current nginx version here

SCRIPTDIR=$( cd $(dirname $0) ; pwd -P ) # Find out what directory we're running in
BDIR="/tmp/boringnginx-$RANDOM" # Set  target build directory

 Handle arguments passed to the script. Currently only accepts the flag to
 include passenger at compile time, but I might add a help section or more options soon.
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

sudo apt remove \
  nginx \
  nginx-common \
  nginx-full \
  nginx-light

sudo apt install \
  build-essential \
  cmake \
  git \
  gnupg \
  gnupg-curl \
  golang \
  libpcre3-dev \
  wget \
  zlib1g-dev \
  libcurl4-openssl-dev

# Build BoringSSL
git clone https://boringssl.googlesource.com/boringssl "$BDIR/boringssl"
cd "$BDIR/boringssl"
mkdir build && cd build
cmake ../
make

# Make an .openssl directory for nginx and then symlink BoringSSL's include directory tree
mkdir -p "$BDIR/boringssl/.openssl/lib"
cd "$BDIR/boringssl/.openssl"
ln -s ../include

# Copy the BoringSSL crypto libraries to .openssl/lib so nginx can find them
cd "$BDIR/boringssl"
cp "build/crypto/libcrypto.a" "build/ssl/libssl.a" ".openssl/lib"

# Download additional modules
git clone https://github.com/openresty/headers-more-nginx-module.git "$BDIR/ngx_headers_more"
git clone https://github.com/simpl/ngx_devel_kit.git "$BDIR/ngx_devel_kit"
git clone https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git "$BDIR/ngx_subs_filter"

# Import nginx team signing keys to verify the source code tarball
gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys $NGXSIGKEY

# Verify and extract nginx sources
cp -f -v "$SCRIPTDIR/src/nginx-$NGXVER.tar.gz" "$BDIR/nginx-$NGXVER.tar.gz"
cp -f -v "$SCRIPTDIR/src/boring.patch" "$BDIR/boring.patch"
if [ ! -f "nginx-$NGXVER.tar.gz" ]; then echo -e "\nFailed to find nginx $NGXVER sources!" && exit 2; fi

verify_sig() {
# This function takes a filename as an argument, and verifies the GPG sig of it.
# If the file passes, it returns an error code of 0 that we can rely on later in the main script.
# If it fails, it returns an error code of 1
  local file=$1
  out=$(gpg --status-fd 1 --verify "$file" 2>/dev/null)
  if  echo "$out" | grep -qs "\[GNUPG:\] GOODSIG" && echo "$out" | grep -qs "\[GNUPG:\] VALIDSIG"
  then
    return 0
  else
    echo "$out" >&2
    return 1
  fi
}

wget --https-only "https://nginx.org/download/nginx-$NGXVER.tar.gz.asc" # Download sig file for this source code tarball
if verify_sig "nginx-$NGXVER.tar.gz.asc" # Verify that our source tarball has been signed with the key from the nginx site
then
  echo "Good signature on source file."
else
  echo "GPG VERIFICATION OF SOURCE CODE FAILED!"
  echo "EXITING!"
  exit 100
fi

# Since we've got this far, it means verification was successful so we can unpack the sources and start working on them
tar zxvf "nginx-$NGXVER.tar.gz"
cd "$BDIR/nginx-$NGXVER"

# Config nginx based on the flags passed to the script, if any
EXTRACONFIG=""
WITHROOT=""
if [ $PASSENGER -eq 1 ]; then
  echo "" && echo "Phusion Passenger module enabled."
  sudo gem install rails
  sudo gem install passenger
  EXTRACONFIG="$EXTRACONFIG --add-module=$(passenger-config --root)/src/nginx_module"
  WITHROOT="sudo " # Passenger needs root to read/write to /var/lib/gems
fi

# Run the config with default options and append any additional options specified by the above section
$WITHROOT./configure \
        --prefix=/usr/share/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib64/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --http-client-body-temp-path=/var/lib/nginx/tmp/client_body \
        --http-proxy-temp-path=/var/lib/nginx/tmp/proxy \
        --http-fastcgi-temp-path=/var/lib/nginx/tmp/fastcgi \
        --http-uwsgi-temp-path=/var/lib/nginx/tmp/uwsgi \
        --http-scgi-temp-path=/var/lib/nginx/tmp/scgi \
        --pid-path=/run/nginx.pid \
        --lock-path=/run/lock/subsys/nginx \
        --user=www-data \
        --group=www-data \
        --with-file-aio \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_realip_module \
        --with-http_addition_module \
        --with-http_sub_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_mp4_module \
        --with-http_geoip_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_random_index_module \
        --with-http_secure_link_module \
        --with-http_degradation_module \
        --with-http_slice_module \
        --with-http_stub_status_module \
        --with-pcre \
        --with-pcre-jit \
        --with-stream \
        --with-stream_ssl_module \
        --with-google_perftools_module \
        --with-cc-opt='-O2 -g -fPIE -pipe -Wall -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-all --param=ssp-buffer-size=4 -grecord-gcc-switches -I ../boringssl/.openssl/include/' \
        --with-ld-opt='-Wl,-z,relro -Wl,-E' \
        --with-openssl="$HOME/boringssl" \
        --add-module="$HOME/ngx_pagespeed-$PSPDVER" \
        --add-module="$HOME/ngx_headers_more" \
        --add-module="$HOME/ngx_devel_kit" \
        --add-module="$HOME/ngx_subs_filter" \
        $EXTRACONFIG

# Fix "Error 127" during build
touch "$BDIR/boringssl/.openssl/include/openssl/ssl.h"

# Fix some other build errors caused by nginx expecting OpenSSL
patch -p1 < "$BDIR/boring.patch"

# Build nginx
make # Fortunately we can get away without root here, even for Passenger installs
sudo make install

# Add systemd service
sudo cp -f -v "$SCRIPTDIR/nginx.service" "/lib/systemd/system/nginx.service"

# Enable & start service
sudo systemctl enable nginx.service
sudo systemctl start nginx.service

# Finish script
echo ""
sudo /usr/sbin/nginx -V
echo ""
sudo ldd /usr/sbin/nginx

# If you previously installed nginx via apt and get errors when trying to boot
# this compiled version, you might need to remove /etc/nginx and then try running
# the buildscript again (or just the 'make install' part)
