# Linux Requirements

* [Z88DK version 2.2](https://github.com/z88dk/z88dk/wiki)
* [bas2tap](https://github.com/speccyorg/bas2tap)
* Perl 5
* Perl modules:
  * `Data::Compare`
  * `List::MoreUtils`
  * `File::Copy`
  * `GD`
  * `YAML`
  * `Algorithm::FastPermute`
  * `Digest::SHA1`
* M4
* Fuse (ZX Spectrum Emulator)
* make
* git

With the exception of Z88DK, all the other modules and requirements are available in standard repos for most distributions

## Specific instructions for Fedora

Enter the following command for installing the required packages:

```
sudo dnf install -y perl perl-Data-Compare perl-List-MoreUtils perl-File-Copy perl-GD perl-YAML m4 make perl-Algorithm-FastPermute
```

## Specific instructions for Ubuntu, Debian and Linux Mint

Enter the following command for installing the required packages:

```
sudo apt install -y perl libdata-compare-perl liblist-moreutils-perl libgd-perl libyaml-perl m4 make
```

# Windows Requirements

* [Z88DK](https://github.com/z88dk/z88dk/wiki)
* [CYGWIN GNU Distribution for Windows](https://cygwin.com/install.html).
* On CYGWIN installation, select at least the following packages in addition to the default packages:
  * m4
  * make
  * perl
  * perl-Data-Compare
  * perl-List-MoreUtils
  * perl-File-Copy
  * perl-GD
  * perl-YAML
* [Fuse (ZX Spectrum Emulator)](https://sourceforge.net/projects/fuse-emulator/files/fuse/)

Alternatively, you can just launch a WSL2 session with Ubuntu 22.04, and
follow the Linux installation instructions above.
