# gittyup [![Build Status](https://travis-ci.org/disruptek/gittyup.svg?branch=master)](https://travis-ci.org/disruptek/gittyup)
higher-level git bindings that build upon nimgit2

## Usage
Use one of these combinations of defines, in decreasing preference:

```
--define:git2Git --define:git2SetVer="master"
--define:git2DL --define:git2SetVer="0.28.4"
--define:git2Git --define:git2SetVer="v0.28.4"
--define:git2DL --define:git2SetVer="0.28.3"
--define:git2Git --define:git2SetVer="v0.28.3"
```

## Tests

gittyup continuous integration tests run flavors with `--gc:arc`, `cpp`,
`-d:danger`, and the libgit2 versions listed above, on Windows, OS X, and
Linux; they should be pretty comprehensive.

## Documentation
See [the documentation for the gittyup module](https://disruptek.github.io/gittyup/gittyup.html) as generated directly from the source.

## License
MIT
