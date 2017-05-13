BoringNginx
=========
<img align="right" src="https://raw.githubusercontent.com/ajhaydock/BoringNginx/master/nginx.png" alt="Nginx Logo" title="Nginx">
Build script to build current stable Nginx with Google's BoringSSL instead of the default OpenSSL.

Currently, this build script only supports the **latest mainline release** of Nginx.

If you are looking to build Nginx against the latest OpenSSL Beta instead, please check out [this repo here](https://github.com/ajhaydock/Nginx-PageSpeed-OpenSSLBeta).

To build latest supported version (Debian and CentOS supported):
```bash
./build-debian.sh
```
```bash
./build-centos.sh
```

-----------------------------------------


### Disclaimer
I don't recommend running this script on any production machines without going through and testing it first. It's designed to go through and remove any existing `nginx` installation, then compiles nginx and assumes you then want it installed too. It does everything in `/tmp`, which might work for some people, but you might want to change this for other reasons. I'm also not sure how it might interact with other complex setups that people may be running.

If you're running this on a blank machine or inside a Docker container or something, then go right ahead... it should set everything up for you and work pretty much out of the box - but if you're installing this to replace your current version of `nginx` on a production server, I'd recommend maybe going through and running each command manually on an individual basis, or at least testing the script first, then tweaking it to your needs.

With that out of the way, I hope you find some use for this script or these patches. Enjoy! :)

-----------------------------------------


### Quick Deployment with Docker (Recommended!)
[![](https://images.microbadger.com/badges/image/ajhaydock/boringnginx.svg)](https://microbadger.com/images/ajhaydock/boringnginx "Get your own image badge on microbadger.com")

The [Docker Hub](https://hub.docker.com/r/ajhaydock/boringnginx/) images for this project allow for mostly instant setup of a working instance of my BoringNginx build. You can deploy a test version of this instance (currently built on top of Docker's official CentOS 7 image):
```bash
docker run --cap-drop=all --name boringnginx -d -p 80:8080 ajhaydock/boringnginx
```

Alternatively, you can clone this repo and build the Docker container directly.

Enter the directory containing the Dockerfile you want to build an image for, and build it with something like:
```bash
docker build -t boringnginx .
```

Running a manually-built container is similar to the above:
```bash
docker run --cap-drop=all --name nginx -d -p 80:8080 boringnginx
```

You can also automate the run command with a systemd service or something similar. This is probably how you will want to do it if you're customising this and using it to deploy a site in production. Creating a systemd service that calls the `docker run` command means you will end up with a webserver that basically operates as a normal installation of nginx would operate - but containerized as an all-in-one distribution.

Obviously, this built container will not contain any of your site data, your `nginx.conf,` or your SSL keys. You probably want to look at the [Docker Volumes](https://docs.docker.com/engine/tutorials/dockervolumes/) documentation for information on giving the container access to these in a location on your host machine. This will probably be done by adding a few `-v` flags to the `docker run` examples above. Please note that the user the nginx process runs under within the container will have the UID of `666` by default, and any files or directories you pass through to the container should be owned by this UID (it does not matter if there is no user with this UID on your host system).

-----------------------------------------


### Enabling PHP
To enable PHP on this installation of nginx, it is as simple as installing the `php5-fpm` package (`php-fpm` on CentOS/Fedora) and adding the regular PHP directives to your `/etc/nginx/nginx.conf` file. On Grsec/PaX kernels you do not need to set any MPROTECT exceptions on any binaries to get a fully working server with PHP support (I have tested this).

To enable PHP, I add the following to my `nginx.conf` server block. The `try_files` directive ensures that Nginx does not forward bad requests to the PHP processor, but you may need to tweak this for your specific web application:
```nginx
	location ~ \.php$ {
		try_files $uri =404;
		fastcgi_split_path_info ^(.+\.php)(/.+)$;
		fastcgi_pass unix:/var/run/php5-fpm.sock; # Debian-based
#		fastcgi_pass unix:/run/php-fpm/www.sock; # Fedora-based
		fastcgi_index index.php;
		fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
		include fastcgi_params;
	}
```

You will also need to ensure that the `index` directive of your site is set up to serve `index.php` files.

-----------------------------------------


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
