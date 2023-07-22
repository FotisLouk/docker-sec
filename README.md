# docker-sec
Automatic AppArmor management for Docker containers

## Usage
To use *docker-sec* simply use docker commands by appending the suffix **-sec**. For example to start a new container run the following command:

```bash
docker-sec run --name safe-nginx -p 80:80 nginx
```
To use the profile training feature of docker-sec user can do the following:
```bash
docker-sec train-start safe-nginx
#browse nginx pages...
docker-sec train-stop safe-nginx
```
At this point the containers runs with an Apparmor profile generated based on the permissions required during the training period.
To get more information about the container and the profiles associated run:
``` bash
docker-sec run safe-nginx
```

## Installation
To install docker-sec, first of all AppArmor must be installed and enabled.
Also, auditd must be installed in system. For Debian based systems run:

```bash
sudo apt-get install auditd audispd-plugins
```

As a next step, clone docker-sec from github and move contents of folder *profiles* to */etc/apparmor.d*. Once done, add *usr.bin.docker-runc* in kernel in enforce mode using the following command:

```bash
sudo aa-enforce /etc/apparmor.d/usr.bin.docker-runc
```

Finally docker-sec script should be added to PATH environment variable.

Docker-sec is ready to protect your containers!

## Compatibility
Please note that dokcer-sec has been tested with the following versions (on amd64):
 * **Ubuntu**: 16.04.02 LTS using kernel 4.4 (4.4.0-66-generic)
 * **Docker**: 1.12.6 (Client & Server), API Version: 1.24, Build from commit 78d1802 (dpkg package: docker 1.5-1 -amd64)
   * Runtime: runc 1.0.0-rc2-dev
   * Storage driver: aufs
 * **Apparmor**: 2.10.95
 * **auditd**: 1:2.4.5-1ubuntu2

## License
Apache License v2.0 (see [LICENSE](https://github.com/FotisLouk/docker-sec/blob/master/LICENSE.md) file for more information)