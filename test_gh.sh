#!/bin/bash
TMPDIR=$(mktemp -d)
echo "Temp directory: $TMPDIR"

if [ -z "$TMPDIR" ]; then
  echo "Failed to create temp directory"
  exit 1
fi

docker run --privileged -v /var/run/docker.sock:/var/run/docker.sock -v .:/workdir -w /workdir --network host --rm $(docker build --rm -q act) act --artifact-server-path "$TMPDIR/" -P ubuntu-latest=catthehacker/ubuntu:act-latest --rm push -j build

echo "Deleting temp directory: $TMPDIR"
rm -rf "$TMPDIR"
