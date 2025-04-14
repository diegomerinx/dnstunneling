#!/bin/bash

[ "$UID" -eq 0 ] || exec sudo "$0" "$@"

domain="$1"

sudo iodine -f -r -P password $domain
