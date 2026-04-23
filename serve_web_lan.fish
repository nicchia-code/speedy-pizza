#!/usr/bin/env fish

set -lx HOME /tmp
set -lx XDG_CONFIG_HOME /tmp
set -lx DART_SUPPRESS_ANALYTICS true
set -lx FLUTTER_SUPPRESS_ANALYTICS true

set port 8080
if test (count $argv) -ge 1
    set port $argv[1]
end

flutter build web
or exit 1

cd build/web
or exit 1

python3 -m http.server $port --bind 0.0.0.0
