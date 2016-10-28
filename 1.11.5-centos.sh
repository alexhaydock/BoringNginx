#!/bin/bash
set -u
shopt -s extglob
if [ "$(id -u)" -eq 0 ]; then echo -e "This script is not intended to be run as root.\nExiting." && exit 1; fi


## Note to self. (For use when generating patches).
# diff -ur nginx-1.11.5/ nginx-1.11.5-patched/ > ../boring.patch


rpath="$(cd $(dirname $0) && pwd)" # Run path
bdir="/tmp/boringnginx-$RANDOM" # Set build directory

ngxver="1.11.5"		# Target nginx version
libresslver="2.4.2"	# LibreSSL version


# Handle arguments passed to the script. Currently only accepts the flag to
# include passenger at compile time,but I might add a help section or more options soon.
PASSENGER=0
while [ "$#" -gt 0 ]; do
	case $1 in
		--passenger|-passenger|passenger) PASSENGER="1"; shift 1;;
		*) echo "Invalid argument: $1" && exit 10;;
	esac
done


# Prompt our user before we start removing stuff
CONFIRMED=0
echo -e "This script will remove any versions of Nginx you installed using yum, and\nreplace any version of Nginx built with a previous version of this script."
while true
do
	echo ""
	read -p "Do you wish to continue? (Y/N)" answer
	case $answer in
		[yY]* )
			CONFIRMED=1
			break;;

		* )
			echo "Please enter 'Y' to continue or use ^C to exit.";;
	esac
done
if [ "$CONFIRMED" -eq 0 ]; then echo -e "Something went wrong.\nExiting." && exit 1; fi


# Install deps
sudo systemctl stop nginx
sudo systemctl disable nginx
sudo yum -y install cmake gcc gcc-c++ gd-devel GeoIP-devel git golang libxslt-devel patch pcre-devel perl-devel perl-ExtUtils-Embed rpm-build wget


# Prepare nginx source
mkdir "$bdir" && mkdir -p "$rpath/source" && cd "$rpath/source"
[ $(($(expr $ngxver : '..\([0-9]*\).*')%2)) -eq 1 ] && Mainline=mainline/
[ ! -e nginx-$ngxver-1.el7.ngx.src.rpm ] && curl -LO --retry 3 "http://nginx.org/packages/${Mainline}centos/7/SRPMS/nginx-${ngxver}-1.el7.ngx.src.rpm"
rpm -ih --define "_topdir $bdir" "nginx-$ngxver-1.el7.ngx.src.rpm"


# Build BoringSSL
if [ -e "${rpath}/boringssl" ]
then
	cd "${rpath}/boringssl"
	git fetch && git pull
else
	git clone "https://boringssl.googlesource.com/boringssl" "${rpath}/boringssl"
fi

cp -r "${rpath}/boringssl" "$bdir/SOURCES"
mkdir -p "${bdir}/SOURCES/boringssl/build" && cd "${bdir}/SOURCES/boringssl/build"
cmake ../ && make
mkdir -p "${bdir}/SOURCES/boringssl/.openssl/lib"
cd "${bdir}/SOURCES/boringssl/.openssl" && ln -s ../include
cd "${bdir}/SOURCES/boringssl" && cp "build/crypto/libcrypto.a" "build/ssl/libssl.a" ".openssl/lib"
cp "${rpath}/patches/$ngxver.patch" >> "${bdir}/SOURCES/boring.patch"


# Config nginx based on the flags passed to the script, if any
if [ $PASSENGER ]
then
    [ ! $(gem list rails | grep rails) ] && sudo gem install rails -v 4.2.7
    [ ! $(gem list passenger | grep passenger) ] && sudo gem install passenger
fi


# Setup RPM Spec
patch "${bdir}/SPECS/nginx.spec" "${rpath}/patches/$ngxver-centos-spec.patch"
[ $PASSENGER ] && EXTRACONFIG="$EXTRACONFIG --add-module=$(passenger-config --root)/src/nginx_module"
sed -i "1 i\%define EXTRACONFIG ${EXTRACONFIG-;}" "${bdir}/SPECS/nginx.spec"
sed -i "1 i\%define dist .el%{rhel}" "${bdir}/SPECS/nginx.spec"


# Build Nginx RPM
if [ $PASSENGER ]
then
    sudo -i -u root bash -c "PATH=/usr/local/bin:$PATH rpmbuild -bb --define '_topdir $bdir' ${bdir}/SPECS/nginx.spec"
else
    rpmbuild -bb --define "_topdir $bdir" "${bdir}/SPECS/nginx.spec"
fi
sudo chown -R $USER "$bdir"


# Install
sudo rpm -iv --replacepkgs "${bdir}/RPMS/${HOSTTYPE}/nginx-*.rpm"
sudo systemctl daemon-reload
echo ""
nginx -V
echo ""
ldd /usr/sbin/nginx
echo ""
echo "Install complete!"
echo "You can start/enable nginx with systemctl command:"
echo ""
echo "    sudo systemctl start nginx"
echo "    sudo systemctl enable nginx"
echo ""
