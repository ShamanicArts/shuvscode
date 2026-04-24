#!/usr/bin/env bash
exec /opt/shuvscode/shuvcode \
  --enable-features=UseOzonePlatform \
  --ozone-platform-hint=auto \
  "$@"
