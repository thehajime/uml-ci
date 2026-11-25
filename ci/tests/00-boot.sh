#!/bin/sh
# Userspace started and procfs exposes the running kernel release.
read -r release < /proc/sys/kernel/osrelease && [ -n "$release" ]
