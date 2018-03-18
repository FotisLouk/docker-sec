# docker-sec
Automatic AppArmor management for Docker containers

## Usage
To use *docker-sec* simply use docker commands by appending the suffix **-sec**. For example to start a new container run the following command:

```bash
docker-sec run --name safe-nginx -p 80:80 nginx
```
To use the profile training feature of docker-sec user can do the following:
```bash
docker-sec train-stop safe-nginx
#browse nginx pages...
docker-sec train-stop safe-nginx
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

## License
Apache License v2.0 (see [LICENSE](https://github.com/FotisLouk/docker-sec/blob/master/LICENSE.md) file for more information)