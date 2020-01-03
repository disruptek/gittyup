import std/uri
import std/strutils
import std/os
import std/unittest

import gittyup

const
  v1 = "555d5d803f1c63f3fad296ba844cd6f718861d0e"
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
        count = 0
      for thing in cloned.commitsForSpec(@[dotnimble]):
        check thing.isOk
        free thing.get
        count.inc
      check count > 10
