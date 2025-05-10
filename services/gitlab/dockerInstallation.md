# How to deploy gitlab via docker?

## Prerequisites

`docker` and `docker-compose` installed, simply doing `sudo apt install docker.io` will do the trick

## Now what?

The [Officials](https://docs.gitlab.com/install/docker/installation/) say you will also need a domain too, but we don't, so.

never mind, lets do the shit:

### step 1

make some direcotory to store gitlab shits:

```bash
sudo mkdir -p /srv/gitlab
```

add it to var env, if using bash:

```bash
sudo nano ~/.bashrc
```

and add:

```bash
export GITLAB_HOME=/srv/gitlab
```

### step 2

find the tag you want [here](https://hub.docker.com/r/gitlab/gitlab-ce/tags/) and we will only need like this part `gitlab/gitlab-ee:<version>-ee.0`, just do not use `latest`, I guess.

### step 3

I'm now doing this docker compose,

- it will be updated if any problem

this is what it should be if using a proper domain:

```yml
services:
  gitlab:
    image: gitlab/gitlab-ce:17.11.2-ce.0
    container_name: gitlab
    restart: always
    hostname: "gitlab.local"
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://gitlab.example.com:8929'; #Or just put your STATIC, afai got it
        gitlab_rails['gitlab_shell_ssh_port'] = 2424
    ports:
      - "8929:80"
      - "4430:443"
      - "2424:22"
    volumes:
      - "$GITLAB_HOME/config:/etc/gitlab"
      - "$GITLAB_HOME/logs:/var/log/gitlab"
      - "$GITLAB_HOME/data:/var/opt/gitlab"
```

now hear me, we probaly can ignore the `external_url` part, but I see its not recommended, so I came with a , potentially, clever idea, first I add this `env var` :

```bash
export HOST_IP=$(hostname -I | awk '{print $1}')  # gets first non-loopback IP
```

it's not real-time, but this does the job, now:

```yml
services:
  gitlab:
    image: gitlab/gitlab-ce:17.11.2-ce.0
    container_name: gitlab
    restart: always
    hostname: "gitlab.local"
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://${$HOST_IP}:8998';
        gitlab_rails['gitlab_shell_ssh_port'] = 2222
    ports:
      - "8998:80"
      - "4430:443"
      - "2222:22"
    volumes:
      - "$GITLAB_HOME/config:/etc/gitlab"
      - "$GITLAB_HOME/logs:/var/log/gitlab"
      - "$GITLAB_HOME/data:/var/opt/gitlab"
```

update:

```yml
is this an ok shit:
services:
  gitlab:
    image: gitlab/gitlab-ce:17.11.2-ce.0
    container_name: gitlab
    restart: always
    hostname: "gitlab.local"
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        gitlab_rails['gitlab_shell_ssh_port'] = 2222
    ports:
      - "8998:80"
      - "4430:443"
      - "2222:22"
    volumes:
      - "$GITLAB_HOME/config:/etc/gitlab"
      - "$GITLAB_HOME/logs:/var/log/gitlab"
      - "$GITLAB_HOME/data:/var/opt/gitlab"
```

- for some reason
  `external_url 'http://${HOST_IP}:8998';` did not work for now, so I removed it. note that I can do `echo $HOST_IP`.
  update:
  probably the HOST_UP is not properly passed to the shit. OR MAYBE, I didn't wait for it to boot.OR WORSE, this shit has problem with this prop in general. what to do?
  update:
  the problem is with the whole shit, idk, some internal nginx that does not work with ip? I'm ignoring it for now.

- also we should do a predefined root user and password

```bash
      GITLAB_ROOT_EMAIL: "admin@BuildWithLal.com"
      GITLAB_ROOT_PASSWORD: "Abcd@0123456789"
```

I'm not sure if its safe or not, I guess the better way is to look at auto generated password here:

```bash
docker exec -it gitlab cat /etc/gitlab/initial_root_password
# OR
cat $GITLAB_HOME/config/initial_root_password
```

and default username is `root`

### step 4

lets do `docker compose up -d` to see if its working.
(also if you are using older version of docker compose, lazy like me, do `docker-compose up -d`)
