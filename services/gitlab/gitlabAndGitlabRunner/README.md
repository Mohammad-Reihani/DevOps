# Steps to deploy gitlab and gitlab-runner together on a server

## 1. Do you have docker?

Make sure you have docker installed. if you're using new ones, you should change `docker-compose` command to `docker compose` in `start.sh`

> Note: you may install it via:

1. `snap`: `sudo snap install docker` or view versions `snap info docker`

## 2. Define Env vars

define these in `~/.bashrc`:

```bash
# Gitlab Related
export GITLAB_HOME=/srv/gitlab
export GITLAB_RUNNER_HOME=/srv/gitlab-runner
export HOST_IP=$(hostname -I | awk '{print $1}')  # gets first non-loopback IP
```

If these variables are not set, the `start.sh` script will check for these create them, BUT, if the script does that you should either do `source ~/.bashrc` and rerun the script or open a new terminal and run the script.

## 3. Run the `start.sh`

run this script so it will create the network `gitlab-net` and also bring up the docker compose.

this gitlab and gitlab-runner better be on the same local network, so setup, communication between them and everything will be so much faster and easier.

If you look into the `docker-compose` there is a `patch-runner` its a lightweight linux to make sure both of these are on the same network.

> Note: since they ARE in the same network, when registering `gitlab-runner` make sure you use the correct `local address` not your external address of gitlab.

## 4. register the gitlab runner

```bash
docker exec -it gitlab-runner gitlab-runner register
```

NOTE: gitlab address should be this when it asks you, also get the registration token via:

```bash
Enter the GitLab instance URL:  http://gitlab:8998/

Enter the registration token: Get it from GitLab → Admin → CI/CD → Runners
```

Note: default password for gitlab is in:

```bash
# Container
cat /etc/gitlab/initial_root_password
# Your local machine
cat /srv/gitlab/config/initial_root_password
```

or more precisely:

```bash
cat $GITLAB_HOME/config/initial_root_password
```

## 5. Load any custom image to build your app

You can build it again in your server with:

```bash
docker build -t react-native-android-builder:latest
```

Or load it:

```bash
xz -d -c my-image.tar.xz | docker load
```
