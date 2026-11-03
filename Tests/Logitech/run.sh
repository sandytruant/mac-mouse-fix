#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/mmf-logitech-tests.XXXXXX)
trap 'rm -rf "$work"' EXIT
xcrun clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined Tests/Logitech/protocol-state.c -o "$work/protocol"
"$work/protocol"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Wno-unused-parameter -I Tests/Logitech/stubs -fsanitize=address,undefined Tests/Logitech/lifecycle.m -framework Foundation -framework AppKit -framework IOKit -framework CoreGraphics -o "$work/lifecycle"
"$work/lifecycle"
