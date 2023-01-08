# Docker Usage

The Makefile in this directory builds a Docker image which includes Z88DK
and all RAGE1 dependencies and tools, ready for use. The image is based on
Fedora, as this is my main development environment.

It is intended to make it easier to start coding RAGE1 without having to
worry about the correct dependencies.

To create the Docker image, run `make build-image` in this directory. This
will create a Docker image with name `z88dk-rage1` and tag `latest`

After that, run the following command line to start a new container with the
created image and run an shell session inside (replace the `/your/src/dir`
part with the base directory where your projects live):

```
docker run -it --mount type=bind,source=/your/src/dir,target=/src z88dk-rage1:latest /bin/bash
```

When using this session, all the needed Z88DK tools and paths are already
preconfigured and ready to be used. RAGE1 is configured by default to
search for its helper tools in the correct directories in the Docker image.
