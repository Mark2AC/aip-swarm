#!/bin/bash
# Source ROS2, build the workspace if needed, then exec the launch command.
#
# `src/` is bind-mounted by docker-compose so it always reflects the host.
# We build into /ws/build + /ws/install which live inside the container's
# writable layer (or in a named volume if compose provides one). Using
# `exec` at the end preserves PID 1 so SIGTERM from `docker stop`
# propagates to ros2 launch and its child nodes.
#
# Incremental rebuilds: if /ws/install already exists we skip the build.
# To force a rebuild (e.g. after msg/srv changes), either:
#   docker compose restart sim   # no effect — install/ persists
#   docker compose down && up    # install/ is in container layer, lost → rebuild
#   OR touch a sentinel file:    ros2 daemon stop; rm -rf /ws/install /ws/build
set -e

source /opt/ros/humble/setup.bash

if [ ! -f /ws/install/setup.bash ]; then
    echo "[entrypoint] install/ not found — running first-time colcon build"
    cd /ws
    colcon build --symlink-install --event-handlers console_direct+
    echo "[entrypoint] build finished"
fi

source /ws/install/setup.bash
exec "$@"
