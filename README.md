# gittyup

[![Test Matrix](https://github.com/disruptek/gittyup/workflows/CI/badge.svg)](https://github.com/disruptek/gittyup/actions?query=workflow%3ACI)
[![GitHub release (latest by date)](https://img.shields.io/github/v/release/disruptek/gittyup?style=flat)](https://github.com/disruptek/gittyup/releases/latest)
![Minimum supported Nim version](https://img.shields.io/badge/nim-1.0.8%2B-informational?style=flat&logo=nim)
[![License](https://img.shields.io/github/license/disruptek/gittyup?style=flat)](#license)
[![buy me a coffee](https://img.shields.io/badge/donate-buy%20me%20a%20coffee-orange.svg)](https://www.buymeacoffee.com/disruptek)

This is a _higher_-level and idiomatic abstraction for
[libgit2](https://libgit2.org/) that builds upon the
[nimgit2](https://github.com/genotrance/nimgit2) wrapper produced by
[nimterop](https://github.com/nimterop/nimterop).

## Installation

```
$ nimph clone disruptek/gittyup
```
or if you're still using Nimble like it's 2012,
```
$ nimble install https://github.com/disruptek/gittyup
```

## Usage

You need a libgit2 >= 1.0.0; I recommend one of these combinations of build
flags:

```
# build libraries from scratch using the libgit2 repo
--define:git2Git --define:git2SetVer="v1.0.1"
# use your system's libgit2
--define:git2Std --define:git2SetVer="1.0.1"
# use pre-built Julia Binaries
--define:git2JBB --define:git2SetVer="1.0.1"
```

This gives some idea for the usage:

```nim
import gittyup

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
    of grcExists:
      error dir, " already exists, i guess"
    of grcNotFound:
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

## Tests

gittyup continuous integration tests run flavors with `--gc:arc`, `cpp`,
`-d:danger`, and the libgit2 versions listed above, on Windows, OS X, and
Linux; they should be pretty comprehensive.

## Documentation

See [the documentation for the gittyup module](https://disruptek.github.io/gittyup/gittyup.html) as generated directly from the source.  I often find
[the libgit2 reference documentation site](https://libgit2.org/) useful
as well.

## License
MIT
