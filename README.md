# gittyup
higher-level git bindings that build upon nimgit2

- `nim-1.0` [![Build Status](https://travis-ci.org/disruptek/gittyup.svg?branch=master)](https://travis-ci.org/disruptek/gittyup)
- `arc +/ nim-1.3` [![Build Status](https://travis-ci.org/disruptek/gittyup.svg?branch=devel)](https://travis-ci.org/disruptek/gittyup)
- `arc +/ cpp / nim-1.3` [![Build Status](https://travis-ci.org/disruptek/gittyup.svg?branch=cpp)](https://travis-ci.org/disruptek/gittyup)

## Usage
Use one of these combinations of defines, in decreasing preference:

```
--define:git2Git --define:git2SetVer="master"
--define:git2DL --define:git2SetVer="0.28.4"
--define:git2Git --define:git2SetVer="v0.28.4"
--define:git2DL --define:git2SetVer="0.28.3"
--define:git2Git --define:git2SetVer="v0.28.3"
```

This gives some idea for the syntax at present:

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
See [the documentation for the gittyup module](https://disruptek.github.io/gittyup/gittyup.html) as generated directly from the source.

## License
MIT
