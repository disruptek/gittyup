# gittyup

[![Test Matrix](https://github.com/disruptek/gittyup/workflows/CI/badge.svg)](https://github.com/disruptek/gittyup/actions?query=workflow%3ACI)
[![GitHub release (latest by date)](https://img.shields.io/github/v/release/disruptek/gittyup?style=flat)](https://github.com/disruptek/gittyup/releases/latest)
![Minimum supported Nim version](https://img.shields.io/badge/nim-1.2.13%2B-informational?style=flat&logo=nim)
[![License](https://img.shields.io/github/license/disruptek/gittyup?style=flat)](#license)

This is a _higher_-level and idiomatic abstraction for
[libgit2](https://libgit2.org/) that builds upon the
[hlibgit2](https://github.com/haxscramper/hlibgit2) and
[hlibssh2](https://github.com/haxscramper/hlibssh2) wrappers; the user supplies
the underlying libgit2 and libssh2 libraries in the environment.

## Usage

We test with `libgit2-1.7.1` though earlier versions may work.

This gives some idea for the usage:

```nim
import logging
import gittyup
import uri

# a simple example of cloning a repo
block cloning:
  let
    url = parseURI"https://github.com/disruptek/gittyup"
    dir = "/some/where/gitty"

  # perform a clone; repo is a GitRepository object
  repo := clone(url, dir):
    # this is your error handler;
    # code is an enum of GitResultCode
    case code:
    of GIT_EEXISTS:
      error dir, " already exists, i guess"
    of GIT_ENOTFOUND:
      error url, " isn't a git url, maybe"
    else:
      # an error string more specific than $code
      error code.dumpError

    # you don't have to leave, but i recommend it
    break

  # repo is symbol pointing to a GitRepository here

  # "manual" call invocation means you perform your
  # own memory work, but it's sometimes more ideal
  let
    head = repo.headReference

  # using result semantics...
  if head.isErr:
    echo "error code: ", head.error
  else:
    echo "head oid: ", head.get.oid

# repo is now out of scope and will be freed automatically
```

## Installation

```
$ nimph clone gittyup
```
or if you're still using Nimble like it's 2012,
```
$ nimble install https://github.com/disruptek/gittyup
```

## Documentation

See [the documentation for the gittyup module](https://disruptek.github.io/gittyup/gittyup.html) as generated directly from the source.  I often find
[the libgit2 reference documentation site](https://libgit2.org/) useful
as well.

## License
MIT
