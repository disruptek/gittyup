import std/tables
import std/uri
import std/strutils
import std/os
import std/unittest

import gittyup

const
  v1 = "555d5d803f1c63f3fad296ba844cd6f718861d0e"
  v102 = "372deb094fb11e56171e5c9785bd316577724f2e"
  cloneme = parseURI"https://github.com/disruptek/gittyup"

suite "gittyup":
  setup:
    check init()
    let
      tmpdir = getTempDir() / "gittyup-" & $getCurrentProcessId() / ""
    removeDir(tmpdir)
    check not tmpdir.existsOrCreateDir
    repo := openRepository(getCurrentDir()):
      checkpoint code.dumpError
      check false

  teardown:
    check shutdown()
    removeDir(tmpdir)

  test "zero errors":
    when defined(posix):
      check grcOk.dumpError == ""
    else:
      # windows apparently errors on missing .gitconfig
      check true

  test "repo state":
    check repo.repositoryState == grsNone

  test "get the head":
    head := repo.repositoryHead:
      checkpoint code.dumpError
      check false
    let
      oid = head.oid
    check $oid != ""

  test "get a thing for 1.0.0":
    thing := repo.lookupThing("1.0.0"):
      checkpoint code.dumpError
      check false
    check $thing.oid == v1

  test "remote lookup":
    origin := repo.remoteLookup("origin"):
      checkpoint code.dumpError
      check false
    check "gittyup" in origin.url.path

  test "clone something":
    # clone ourselves into tmpdir
    cloned := cloneme.clone(tmpdir):
      checkpoint code.dumpError
      check false
    check grsNone == cloned.repositoryState

  test "commits for spec":
    # clone ourselves into tmpdir
    cloned := cloneme.clone(tmpdir):
      checkpoint code.dumpError
      check false
    check grsNone == cloned.repositoryState
    let
      dotnimble = "gittyup.nim"
    block found:
      var
        things: seq[GitThing] = @[]
      for thing in cloned.commitsForSpec(@[dotnimble]):
        check thing.isOk
        things.add thing.get
      check things.len > 10
      block found:
        for thing in things.items:
          if $thing.oid == v102:
            break found
          free thing
        check false

    test "create and delete a tag":
      tags := repo.tagTable:
        checkpoint code.dumpError
        check false
      if "test" in tags:
        check repo.tagDelete("test") == grcOk
      thing := repo.lookupThing "HEAD":
        checkpoint code.dumpError
        check false
      let
        oid = thing.tagCreate "test"
      if oid.isErr:
        checkpoint oid.error.dumpError
        check false
      else:
        check repo.tagDelete("test") == grcOk
        dealloc oid.get
