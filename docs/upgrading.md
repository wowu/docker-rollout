---
title: Upgrading
nav_order: 5
---

# Upgrading docker rollout

All existing Docker Rollout versions are backwards compatible. You can upgrade to the latest version by downloading the script again.

1. Check the current plugin version:

   ```bash
   docker rollout --version
   #=> docker-rollout version v0.10
   ```

   or if version option is not available:

   ```bash
   ~/.docker/cli-plugins/docker-rollout docker-cli-plugin-metadata
   #=> ...
   #=> "Version": "v0.10",
   #=> ...
   ```

2. If new version is available, download the latest version:

   ```bash
   curl https://raw.githubusercontent.com/wowu/docker-rollout/master/docker-rollout -o ~/.docker/cli-plugins/docker-rollout
   ```

   You can check the latest version on the [releases page](https://github.com/wowu/docker-rollout/releases).

3. You may need to make the file executable again:

   ```bash
   chmod +x ~/.docker/cli-plugins/docker-rollout
   ```
