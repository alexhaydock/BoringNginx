# Automated container builds for my BoringNginx (nginx + BoringSSL) custom build.

# To run this container from Docker Hub, try a command like:
#
#     docker run --name nginx -d -p 80:80 ajhaydock/boringnginx
#

FROM debian:jessie
MAINTAINER Alex Haydock <alex@alexhaydock.co.uk>

ENV NGXVERSION 1.11.6
ENV HOME /root

WORKDIR $HOME

# Install deps
RUN apt-get update && apt-get install -y \
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

# Import nginx team signing keys
RUN wget --https-only "https://nginx.org/keys/aalexeev.key" && gpg --import "aalexeev.key" \
	&& wget --https-only "https://nginx.org/keys/is.key" && gpg --import "is.key" \
	&& wget --https-only "https://nginx.org/keys/mdounin.key" && gpg --import "mdounin.key" \
	&& wget --https-only "https://nginx.org/keys/maxim.key" && gpg --import "maxim.key" \
	&& wget --https-only "https://nginx.org/keys/sb.key" && gpg --import "sb.key" \
	&& wget --https-only "https://nginx.org/keys/nginx_signing.key" && gpg --import "nginx_signing.key"

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

CMD ["nginx", "-g", "daemon off;"]
