#!/bin/bash
set -xe
if [ "$EUID" -ne 0 ]; then echo "This script requires root to issue Docker commands."; exit; fi

docker build -t registry.gitlab.com/alexhaydock/boringnginx .
docker push registry.gitlab.com/alexhaydock/boringnginx
