#!/bin/sh
set -eu
cd /repo/ansible
ansible --version
exec "$@"
