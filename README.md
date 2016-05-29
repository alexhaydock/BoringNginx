# BoringNginx
Build script to build current stable Nginx with Google's BoringSSL instead of the default OpenSSL.

#### Currently Tested Working On:
* **Nginx 1.10.0** - Debian Jessie *(with Grsec/PaX)*, Debian Stretch *(with Grsec/PaX)*
* **Nginx 1.11.0** - Debian Jessie *(with Grsec/PaX)*, Debian Stretch *(with Grsec/PaX)*

### Enabling PHP
To enable PHP on this installation of nginx, it is as simple as installing the `php5-fpm` package and adding the regular PHP directives to your `/etc/nginx/nginx.conf` file. On Grsec/PaX kernels you do not need to set any MPROTECT excaptions on any binaries to get a fully working server with PHP support (I have now tested this).

To enable PHP, I add the following to my `nginx.conf` server block. The `try_files` directive ensures that Nginx does not forward bad requests to the PHP processor:
<pre>
	location ~ \.php$ {
		try_files $uri =404;
		fastcgi_split_path_info ^(.+\.php)(/.+)$;
		fastcgi_pass unix:/var/run/php5-fpm.sock;
		fastcgi_index index.php;
		fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
		include fastcgi_params;
	}
</pre>

You will also need to ensure that the `index` directive of your site is set up to serve `index.php` files.
