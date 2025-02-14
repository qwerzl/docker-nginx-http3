FROM martenseemann/quic-network-simulator-endpoint:latest

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update
RUN apt-get install -qy mercurial build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev curl git cmake ninja-build golang gnutls-bin iptables

RUN useradd nginx

RUN git clone --depth=1 https://github.com/google/boringssl.git

RUN  cd boringssl  && \
  mkdir build && \
  cd build && \
  cmake -GNinja .. && \
  ninja && \
  cd ../.. && \
  mkdir -p boringssl/.openssl/lib && \
  cp boringssl/build/crypto/libcrypto.a boringssl/build/ssl/libssl.a boringssl/.openssl/lib && \
  cd boringssl/.openssl && \
  ln -s ../include . && \
  cd ../..

RUN touch 'boringssl/.openssl/include/openssl/ssl.h'

RUN hg clone http://hg.nginx.org/nginx-quic && hg clone http://hg.nginx.org/njs && cd nginx-quic && hg update 'quic'

RUN cd nginx-quic && \
    ./auto/configure --prefix=/etc/nginx \
    --build=$(hg tip | head -n 1 | awk '{ print $2 }') \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/run/nginx.pid \
    --lock-path=/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-compat \
    --with-debug \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-stream_quic_module \
    --with-http_v3_module \
    --add-module=../njs/nginx \
    --with-cc-opt='-I/boringssl/include -O0 -fno-common -fno-omit-frame-pointer -DNGX_QUIC_DRAFT_VERSION=29 -DNGX_HTTP_V3_HQ=1' \
    --with-ld-opt='-L/boringssl/build/ssl -L/boringssl/build/crypto'

RUN cd nginx-quic && make -j$(nproc)
RUN cd nginx-quic && make install
RUN mkdir -p /var/cache/nginx /var/log/nginx/
RUN nginx -V; nginx -t

RUN echo "-----------------" && ls /usr/lib/nginx/modules && echo "-----------------"

COPY nginx.conf /etc/nginx/
RUN timeout 10 nginx
EXPOSE 80 443
STOPSIGNAL SIGTERM


CMD ["nginx", "-g", "daemon off;"]
