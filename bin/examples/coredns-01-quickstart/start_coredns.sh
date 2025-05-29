#!/usr/bin/env bash

BINARY="../../coredns"

if [ ! -f "$BINARY" ]; then
    echo "coredns is not exists!"
    exit 1
fi

../../coredns --conf corefile