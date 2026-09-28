#!/bin/sh
# chug installer — this is a redirect stub. The canonical installer lives in
# the chug repo (tampajohn/chug/install.sh) and is served from main, so the
# site copy can never drift. See: https://chug.sh
exec sh -c "$(curl -fsSL https://raw.githubusercontent.com/tampajohn/chug/main/install.sh)"
