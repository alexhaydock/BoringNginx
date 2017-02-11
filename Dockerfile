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

ENV NGXVERSION 1.11.9
ENV NGXSIGKEY B0F4253373F8F6F510D42178520A9993A1C052F8

# Build as root
USER root
WORKDIR /root

# Install deps
RUN apt-get clean && apt-get update && apt-get upgrade -y && apt-get install -y \
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
  zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

# Build BoringSSL
RUN git clone https://boringssl.googlesource.com/boringssl "$HOME/boringssl" \
  && mkdir "$HOME/boringssl/build/" \
  && cd "$HOME/boringssl/build/" \
  && cmake ../ \
  && make \
  && mkdir -p "$HOME/boringssl/.openssl/lib" \
  && cd "$HOME/boringssl/.openssl" \
  && ln -s ../include \
  && cd "$HOME/boringssl" \
  && cp "build/crypto/libcrypto.a" "build/ssl/libssl.a" ".openssl/lib"

# Copy some requirements for building and running nginx into our new container
COPY sources/nginx-$NGXVERSION.tar.gz nginx-$NGXVERSION.tar.gz
COPY patches/$NGXVERSION.patch boring.patch

# Import nginx team signing keys to verify the source code tarball
RUN gpg --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys $NGXSIGKEY

# Verify this source has been signed with a valid nginx team key
RUN wget --https-only "https://nginx.org/download/nginx-$NGXVERSION.tar.gz.asc" \
  && out=$(gpg --status-fd 1 --verify "nginx-$NGXVERSION.tar.gz.asc" 2>/dev/null) \
  && if echo "$out" | grep -qs "\[GNUPG:\] GOODSIG" && echo "$out" | grep -qs "\[GNUPG:\] VALIDSIG"; then echo "Good signature on nginx source file."; else echo "GPG VERIFICATION OF SOURCE CODE FAILED!" && echo "EXITING!" && exit 100; fi

# Configure nginx and related elements
RUN git clone https://github.com/openresty/headers-more-nginx-module.git "$HOME/ngx_headers_more" \
  && tar zxvf nginx-$NGXVERSION.tar.gz \
  && cd "$HOME/nginx-$NGXVERSION/" \
  && ./configure --prefix=/usr/share/nginx \
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
    --add-module="$HOME/ngx_headers_more" \
    --with-openssl="$HOME/boringssl" \
    --with-cc-opt="-g -O2 -fPIE -fstack-protector-all -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security -I ../boringssl/.openssl/include/" \
    --with-ld-opt="-Wl,-Bsymbolic-functions -Wl,-z,relro -L ../boringssl/.openssl/lib" \
  && touch "$HOME/boringssl/.openssl/include/openssl/ssl.h"

# Patch and build nginx
RUN cd "$HOME/nginx-$NGXVERSION/" \
  && patch -p1 < "$HOME/boring.patch" \
  && make \
  && make install

# Make sure the permissions are set correctly on our webroot, logdir and pidfile so that we can run the webserver as non-root.
RUN chown -R www-data:www-data /usr/share/nginx \
  && chown -R www-data:www-data /var/log/nginx \
  && touch /run/nginx.pid \
  && chown -R www-data:www-data /run/nginx.pid

# Configure nginx to listen on 8080 instead of 80 (we can't bind to <1024 as non-root)
RUN perl -pi -e 's,80;,8080;,' /etc/nginx/nginx.conf

# Forward request and error logs to Docker log collector
# (We can do this with access logs too, but I don't intend to expose
# this container directly to the internet and will frontrun it with
# a seperate SSL terminator instead, running a custom nginx build)
RUN ln -sf /dev/stderr /var/log/nginx/error.log

# Command to launch when container is started
WORKDIR /usr/share/nginx

USER www-data
##CMD ["bash"]
CMD ["nginx", "-g", "daemon off;"]
