# BoringNginx
Build script to build current stable Nginx with Google's BoringSSL instead of the default OpenSSL.

#### Currently Tested Working On:
* **Nginx 1.10.0** - Debian Jessie *(with Grsecurity/PaX)*, Debian Stretch *(with Grsecurity/PaX)*
* **Nginx 1.11.0** - Debian Jessie *(with Grsecurity/PaX)*, Debian Stretch *(with Grsecurity/PaX)*

### Note
Please note that I have tested this as a standalone server only, serving static content. In that mode, MPROTECT does not need to be disabled on the nginx binary for it to play well with PaX, but I haven't tested how it interacts with something like the `php5-fpm` package yet.
