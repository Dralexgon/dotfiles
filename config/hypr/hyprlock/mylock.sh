#!/bin/sh

touch /tmp/mylock
echo "$(date +%s)" > /tmp/mylock
hyprlock
