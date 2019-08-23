#!/bin/bash
if [ "$EUID" -eq 0 ]; then echo "Please do not run as root. Please add yourself to the 'docker' group."; exit; fi

docker build -t registry.gitlab.com/alexhaydock/boringnginx .
docker push registry.gitlab.com/alexhaydock/boringnginx
