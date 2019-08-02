# alexhaydock/boringnginx

This container builds the [latest stable Nginx](https://nginx.org/en/CHANGES) with the [latest BoringSSL code](https://boringssl.googlesource.com/boringssl/). It was created to aid with the easy deployment of TLS 1.3 services at a time when most Linux distributions were not packaging a version of OpenSSL that could handle it.

There are versions of this container which build against:
* [BoringSSL](https://gitlab.com/alexhaydock/boringnginx)
* [LibreSSL](https://github.com/alexhaydock/nginx-libressl-latest)
* [OpenSSL](https://github.com/alexhaydock/nginx-openssl-latest)

### Quick Run This Container (Testing on x86_64)
Run this container as a quick test (it will listen on http://127.0.0.1 and you will see logs directly in the terminal when connections are made):
```
docker run --rm -it -p 80:80 gitlab.com/alexhaydock/boringnginx
```

### Quick Run This Container (Production on x86_64)
Run this container as a daemon with your own config file:
```
docker run -d -p 80:80 -p 443:443 -v /path/to/nginx.conf:/etc/nginx.conf:ro --name nginx gitlab.com/alexhaydock/boringnginx
```

### Build This Container Locally
If you have a regular install of Docker on an `x64_64` machine, you can build this container like so:
```
docker build --rm -t boringnginx https://gitlab.com/alexhaydock/boringnginx.git
```

You can now use the same run commands as above, simply substituting `gitlab.com/alexhaydock/boringnginx` with `boringnginx`.

### Running Without Root
You can lock down this container and run without root and dropping all capabilities by using the `--user` and `--cap-drop=ALL` arguments:
```
docker run --rm -it -p 80:8080 --user 6666 --cap-drop=ALL gitlab.com/alexhaydock/boringnginx
```

You will need to make sure that the UID you pick matches the one you have set as the `NGINX_ID` in the `Dockerfile`, and that any configs which you mount into the container are owned by this UID (it does not need to exist on the host system).

If you are running rootless like this, you will also want to ensure that the `nginx.conf` does not attempt to listen on any ports below `1000` (you can still listen on `:80` and `:443` externally since the Docker daemon runs as root and can handle this - Nginx does not need to).
