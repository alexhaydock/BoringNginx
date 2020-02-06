# root trap
ifeq ($(shell id -u),0)
$(error Please do not run this Makefile as root. Please add yourself to the 'docker' group.)
endif

# the build we push to GitLab can't have the MaxMind GeoIP DB in it without violating the license
.PHONY: build
build:
	docker build --pull -t registry.gitlab.com/alexhaydock/boringnginx .

.PHONY: gitlab
gitlab:
	docker push registry.gitlab.com/alexhaydock/boringnginx

.PHONY: push
push: build gitlab

# we can build the geo-enabled container locally if we have a MaxMind GeoIP.conf in this directory
.PHONY: geoip
geoip:
	docker build --pull -t boringnginx-geo -f Dockerfile-geoip .
