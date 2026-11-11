#!/bin/sh

elapsed=$(($(date +%s) - $(cat /tmp/mylock)))
seconds=$((elapsed % 60))
minutes=$(((elapsed / 60) % 60))
hours=$((elapsed / 3600))

printf "%02d:" "$hours"
printf "%02d:" "$minutes"
printf "%02d" "$seconds"

exit
