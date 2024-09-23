#!/bin/bash
docker run --privileged -v /var/run/docker.sock:/var/run/docker.sock -v .:/workdir -w /workdir --rm $(docker build --rm -q act) act push -P ubuntu-latest=catthehacker/ubuntu:act-latest
