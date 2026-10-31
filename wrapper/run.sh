#!/usr/bin/env bash
# mbx — one entrypoint. examples:
#   ./run.sh up          daemon start     ./run.sh status
#   ./run.sh tui         terminal app     ./run.sh key create mykey
#   ./run.sh play "breaking bad" 5x1      ./run.sh dl "peaky blinders" 6x1
cd "$(dirname "$0")"
exec python3 -m moviebox_wrapper "$@"
