# To deploy this container directly from Docker Hub, use:
#
#        docker run --cap-drop=all --name boringnginx -d -p 80:8080 ajhaydock/boringnginx
#
# To build and run this container locally, try a command like:
#
#        docker build -t boringnginx .
#        docker run --cap-drop=all --name boringnginx -d -p 80:8080 boringnginx
#

FROM alpine
MAINTAINER Alex Haydock <alex@alexhaydock.co.uk>

# Nginx Version (See: https://nginx.org/en/CHANGES)
ENV NGXVERSION 1.13.0
ENV NGXSIGKEY B0F4253373F8F6F510D42178520A9993A1C052F8

# PageSpeed Version (See: https://modpagespeed.com/doc/release_notes)
ENV PSPDVER latest-beta

# Build as root (we drop privileges later when actually running the container)
USER root
WORKDIR /root

# Add 'nginx' user
RUN adduser nginx -S -u 666  -h /usr/share/nginx -H

# Update & install deps
RUN apk --no-cache --update add \
      ca-certificates \
      cmake \
      g++ \
      gcc \
      geoip-dev \
      git \
      go \
      gnupg \
      icu \
      icu-libs \
      make \
      linux-headers \
      patch \
      pcre-dev \
      perl \
      tar \
      unzip \
      wget \
      zlib-dev

# Copy nginx source into container
COPY src/nginx-$NGXVERSION.tar.gz nginx-$NGXVERSION.tar.gz
COPY src/nginx.patch nginx.patch

# Import nginx team signing keys to verify the source code tarball (Cannot use HKPS yet with Alpine's version of gnupg)
RUN gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys $NGXSIGKEY

# Verify this source has been signed with a valid nginx team key
RUN wget "https://nginx.org/download/nginx-$NGXVERSION.tar.gz.asc" && \
    out=$(gpg --status-fd 1 --verify "nginx-$NGXVERSION.tar.gz.asc" 2>/dev/null) && \
    if echo "$out" | grep -qs "\[GNUPG:\] GOODSIG" && echo "$out" | grep -qs "\[GNUPG:\] VALIDSIG"; then echo "Good signature on nginx source file."; else echo "GPG VERIFICATION OF SOURCE CODE FAILED!" && echo "EXITING!" && exit 100; fi

# Download and build PageSpeed & PageSpeed Optimization Library (PSOL)
## On Alpine we cannot just grab these prebuilt binaries as they expect us to be
## running a system with glibc, so I have temporarily disabled the PageSpeed module for now.
## To re-enable, make sure to re-add the following line:
##     --add-module="$HOME/ngx_pagespeed-$PSPDVER" \
## to the nginx configure arguments. Some patching will also be required.)
##
RUN echo "Downloading PageSpeed..." && wget -O - https://github.com/pagespeed/ngx_pagespeed/archive/$PSPDVER.tar.gz | tar -xz && \
    cd ngx_pagespeed-$PSPDVER/ && \
    echo "Downloading PSOL..." && \
    PSOLVER=$(basename $(cat PSOL_BINARY_URL) | cut -d"-" -f1) && \
    wget -O - https://dl.google.com/dl/page-speed/psol/$PSOLVER-x64.tar.gz | tar -xz

# Download and build BoringSSL
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

# Download additional modules
RUN git clone https://github.com/openresty/headers-more-nginx-module.git "$HOME/ngx_headers_more" && \
    git clone https://github.com/simpl/ngx_devel_kit.git "$HOME/ngx_devel_kit" && \
    git clone https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git "$HOME/ngx_subs_filter"

# Prepare nginx source
RUN tar -xzvf nginx-$NGXVERSION.tar.gz && \
    rm -v nginx-$NGXVERSION.tar.gz

# Switch directory
WORKDIR "/root/nginx-$NGXVERSION/"

# Configure Nginx
## Config options mostly stolen from the Red Hat package of nginx for Fedora 25.
##
## cc-opt tweaked to use -fstack-protector-all, and -fPIE added to build position-independent.
## Removed any of the modules that the Fedora team was building with "=dynamic" as they stop us being able
## to build with -fPIE and require the less-hardened -fPIC option instead. (https://gcc.gnu.org/onlinedocs/gcc/Code-Gen-Options.html)
##
## Also removed the --with-debug flag (I don't need debug-level logging) and --with-ipv6 as the flag is now deprecated.
## Removed all the mail modules as I have no intention of using this as a mailserver proxy.
## The final tweaks are my --add-module lines at the bottom, and the --with-openssl
## argument, to point the build to the OpenSSL Beta we downloaded earlier.
##
## The Google PerfTools module has also been removed because the package is not available in Alpine:
##     --with-google_perftools_module \
## Re-add with the above line if the package becomes available, or you build it manually.
##
RUN ./configure \
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
        --user=nginx \
        --group=nginx \
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
        --with-cc-opt="-fPIE -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-all -I ../boringssl/.openssl/include/" \
        --with-ld-opt="-Wl,-z,relro" \
        --with-openssl="$HOME/boringssl" \
        --with-openssl-opt=enable-tls1_3 \
        --add-module="$HOME/ngx_headers_more" \
        --add-module="$HOME/ngx_devel_kit" \
        --add-module="$HOME/ngx_subs_filter" && \
    touch "$HOME/boringssl/.openssl/include/openssl/ssl.h"

# Build Nginx
RUN patch -p1 < "$HOME/nginx.patch" && \
    make && \
    make install

# Make sure the permissions are set correctly on our webroot, logdir and pidfile so that we can run the webserver as non-root.
RUN chown -R nginx /usr/share/nginx && \
    chown -R nginx /var/log/nginx && \
    mkdir -p /var/lib/nginx/tmp && \
    chown -R nginx /var/lib/nginx && \
    touch /run/nginx.pid && \
    chown -R nginx /run/nginx.pid

# Configure nginx to listen on 8080 instead of 80 (we can't bind to <1024 as non-root)
RUN perl -pi -e 's,80;,8080;,' /etc/nginx/nginx.conf

# Remove some packages (Doesn't save space because of container's CoW design, but might add a bit of security)
RUN apk del \
      cmake \
      g++ \
      gcc \
      go \
      make

# Print built version
RUN nginx -V

# Launch Nginx in container as non-root
USER nginx
WORKDIR /usr/share/nginx

# Launch command
CMD ["nginx", "-g", "daemon off;"]
