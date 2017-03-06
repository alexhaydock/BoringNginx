# To deploy this container directly from Docker Hub, use:
#
#        docker run --cap-drop=all --name nginx -d -p 80:8080 ajhaydock/boringnginx
#
# To build and run this container locally, try a command like:
#
#        docker build -t boringnginx .
#        docker run --cap-drop=all --name nginx -d -p 80:8080 boringnginx
#

FROM debian:stretch
MAINTAINER Alex Haydock <alex@alexhaydock.co.uk>

ENV NGXVERSION 1.11.10
ENV NGXSIGKEY B0F4253373F8F6F510D42178520A9993A1C052F8

# Build as root
USER root
WORKDIR /root

# Install deps
RUN apt-get install -y \
      build-essential \
      ca-certificates \
      cmake \
      curl \
      dirmngr \
      git \
      gnupg \
      golang \
      libcurl4-openssl-dev \
      libncurses5-dev \
      libpcre3-dev \
      libssl-dev \
      make \
      nano \
      openssl \
      wget \
      zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

# Build BoringSSL
RUN git clone https://boringssl.googlesource.com/boringssl "$HOME/boringssl" && \
    mkdir "$HOME/boringssl/build/" && \
    cd "$HOME/boringssl/build/" && \
    cmake ../ && \
    make && \
    mkdir -p "$HOME/boringssl/.openssl/lib" && \
    cd "$HOME/boringssl/.openssl" && \
    ln -s ../include && \
    cd "$HOME/boringssl" && \
    cp "build/crypto/libcrypto.a" "build/ssl/libssl.a" ".openssl/lib"

# Copy some requirements for building and running nginx into our new container
COPY src/nginx-$NGXVERSION.tar.gz nginx-$NGXVERSION.tar.gz
COPY src/$NGXVERSION.patch boring.patch

# Import nginx team signing keys to verify the source code tarball
RUN gpg --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys $NGXSIGKEY

# Verify this source has been signed with a valid nginx team key
RUN wget --https-only "https://nginx.org/download/nginx-$NGXVERSION.tar.gz.asc" && \
    out=$(gpg --status-fd 1 --verify "nginx-$NGXVERSION.tar.gz.asc" 2>/dev/null) && \
    if echo "$out" | grep -qs "\[GNUPG:\] GOODSIG" && echo "$out" | grep -qs "\[GNUPG:\] VALIDSIG"; then echo "Good signature on nginx source file."; else echo "GPG VERIFICATION OF SOURCE CODE FAILED!" && echo "EXITING!" && exit 100; fi

# Download additional modules
RUN git clone https://github.com/openresty/headers-more-nginx-module.git "$HOME/ngx_headers_more" && \
    git clone https://github.com/simpl/ngx_devel_kit.git "$HOME/ngx_devel_kit" && \
    git clone https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git "$HOME/ngx_subs_filter"

# Prepare nginx source
RUN tar -xzvf nginx-$NGNXVER.tar.gz && \
    rm -v nginx-$NGNXVER.tar.gz

# Switch directory
WORKDIR "$HOME/nginx-$NGXVERSION/"

# Configure nginx
RUN ./configure --prefix=/usr/share/nginx \
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
      --with-cc-opt="-g -O2 -fPIE -fstack-protector-all -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security -I ../boringssl/.openssl/include/" \
      --with-ld-opt="-Wl,-Bsymbolic-functions -Wl,-z,relro -L ../boringssl/.openssl/lib" \
      --with-openssl="$HOME/boringssl" \
      --add-module="$HOME/ngx_pagespeed-$PSPDVER" \
      --add-module="$HOME/ngx_headers_more" \
      --add-module="$HOME/ngx_devel_kit" \
      --add-module="$HOME/ngx_subs_filter" && \
    touch "$HOME/boringssl/.openssl/include/openssl/ssl.h"

# Patch and build nginx
RUN patch -p1 < "$HOME/boring.patch" && \
    make && \
    make install

# Make sure the permissions are set correctly on our webroot, logdir and pidfile so that we can run the webserver as non-root.
RUN chown -R www-data:www-data /usr/share/nginx && \
    chown -R www-data:www-data /var/log/nginx && \
    touch /run/nginx.pid && \
    chown -R www-data:www-data /run/nginx.pid

# Configure nginx to listen on 8080 instead of 80 (we can't bind to <1024 as non-root)
RUN perl -pi -e 's,80;,8080;,' /etc/nginx/nginx.conf

# Print built version
RUN nginx -V

# Launch Nginx in container as non-root
USER www-data
WORKDIR /usr/share/nginx

# Launch command
CMD ["nginx", "-g", "daemon off;"]