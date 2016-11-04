BoringNginx
=========
<img align="right" src="https://raw.githubusercontent.com/ajhaydock/BoringNginx/master/nginx.png" alt="Nginx Logo" title="Nginx">

Build script to build current stable Nginx with Google's BoringSSL instead of the default OpenSSL.

This allows you to use some state-of-the-art crypto features ~~not yet available in the stable branch of OpenSSL~~ (these features [have now entered stable, as of Sep 2016](https://www.openssl.org/news/newslog.html)), like [ChaCha20-Poly1305](https://boringssl.googlesource.com/boringssl/+/de0b2026841c34193cacf5c97646b38439e13200) as a cipher/MAC combo, and [X25519](https://boringssl.googlesource.com/boringssl/+/4fb0dc4b031df7c9ac9d91fc34536e4e08b35d6a) (aka Curve25519) as the ECDHE curve provider if you want to get away from using [unsafe NIST curves](https://safecurves.cr.yp.to/) (though you probably want to check the X25519 [browser support matrix](https://www.chromestatus.com/feature/5682529109540864) before trying that).

| Version      | Tested Working On                      |                               |
|--------------|----------------------------------------|-------------------------------|
| Nginx 1.10.0 | Debian Jessie/Stretch (with Grsec/PaX) |                               |
| Nginx 1.11.0 | Debian Jessie/Stretch (with Grsec/PaX) |                               |
| Nginx 1.11.1 | Debian Jessie/Stretch (with Grsec/PaX) |                               |
| Nginx 1.11.3 | Debian Jessie/Stretch (with Grsec/PaX) |                               |
| Nginx 1.11.4 | Debian Jessie/Stretch (with Grsec/PaX) |                               |
| Nginx 1.11.5 | Debian Jessie/Stretch (with Grsec/PaX) | CentOS 7 (Default el7 Kernel) |

### WARNING!
I don't recommend running this script on any production machines without going through and testing it first. It's designed to go through and remove any existing `nginx` installation, then compiles nginx and assumes you then want it installed too. It does everything in `/tmp`, which might work for some people, but you might want to change this for other reasons. I'm also not sure how it might interact with other complex setups that people may be running.

If you're running this on a blank machine or inside a Docker container or something, then go right ahead... it should set everything up for you and work pretty much out of the box - but if you're installing this to replace your current version of `nginx` on a production server, I'd recommend maybe going through and running each command manually on an individual basis, or at least testing the script first, then tweaking it to your needs.

With that out of the way, I hope you find some use for this script or these patches. Enjoy! :)

### Quick Deployment (Docker)
To make the process of deployment, migration and testing easier, I have created a Docker build for this package. You can find the Dockerfiles in [this repository here](https://github.com/ajhaydock/BoringNginx-Docker) if you want to roll your own, or you can deploy [directly from Docker Hub](https://hub.docker.com/r/ajhaydock/boringnginx/) using a command like this follows:
```
docker run --name nginx-p 80:80 -d ajhaydock/boringnginx
```

### Enabling PHP
To enable PHP on this installation of nginx, it is as simple as installing the `php5-fpm` package and adding the regular PHP directives to your `/etc/nginx/nginx.conf` file. On Grsec/PaX kernels you do not need to set any MPROTECT exceptions on any binaries to get a fully working server with PHP support (I have now tested this).

To enable PHP, I add the following to my `nginx.conf` server block. The `try_files` directive ensures that Nginx does not forward bad requests to the PHP processor, but you may need to tweak this for your specific web application:
```nginx
	location ~ \.php$ {
		try_files $uri =404;
		fastcgi_split_path_info ^(.+\.php)(/.+)$;
		fastcgi_pass unix:/var/run/php5-fpm.sock;
		fastcgi_index index.php;
		fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
		include fastcgi_params;
	}
```

You will also need to ensure that the `index` directive of your site is set up to serve `index.php` files.

### Enabling Passenger (for Ruby-on-Rails)
To enable [Phusion Passenger](https://www.phusionpassenger.com/) in Nginx, you need to compile the Passenger module into Nginx. Passenger has a helpful script to do this for you (`passenger-install-nginx-module`), but that makes it difficult to also compile against BoringSSL. Instead, I have developed a version of this script tweaked for Passenger that you can run after installing the Passenger gem and hopefully enable full Passenger support in Nginx.

Install Ruby:
```bash
sudo apt install ruby ruby-dev
```

Install Rails:
```bash
sudo gem install rails
```

Install Passenger (tool for deploying Rails apps):
```bash
sudo gem install passenger
```

To run the Passenger version of the BoringNginx build script:
```bash
./build-debian.sh --passenger
```

Since building in this fashion bypasses Passenger's auto-compile script that automatically builds its module into Nginx for you, you will also miss out on some of the other things the script does.

If you attempt to run a Rails app and end up with the following in your Nginx `error.log`:
```
The PassengerAgent binary is not compiled. Please run this command to compile it: /var/lib/gems/2.1.0/gems/passenger-5.0.28/bin/passenger-config compile-agent
```

You should be able to fix this by running the following command:
```bash
sudo $(passenger-config --root)/bin/passenger-config compile-agent
```

To find out what configuration directives you need to set inside your `nginx.conf` file before Passenger will function, please see the [Nginx Config Reference](https://www.phusionpassenger.com/library/config/nginx/reference/) page on the Passenger site.

For reference, I added the following lines to the `http {}` block of my Nginx config:
```nginx
	passenger_root			/var/lib/gems/2.1.0/gems/passenger-5.0.28; # This is the result of "passenger-config --root"
	passenger_ruby			/usr/bin/ruby2.1;
```

And the following line to my `server {}` block:
```nginx
	passenger_enabled		on;
```

If you have `location {}` blocks nested within your `server {}` block, you need to make sure that the `passenger_enabled on;` directive seen above is included in every location block that should be serving a Rails app.
