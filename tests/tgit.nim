import std/tables
import std/uri
import std/strutils
import std/os
import std/unittest

import gittyup

const
  tagging = true
  tagtable = true
  specing = true
  v1 = "555d5d803f1c63f3fad296ba844cd6f718861d0e"
  v102 = "372deb094fb11e56171e5c9785bd316577724f2e"
  cloneme = parseURI"https://github.com/disruptek/gittyup"

template cleanup(directory: string) =
  try:
    removeDir(directory)
    check not existsOrCreateDir(directory)
  except OSError as e:
    echo "error removing ", directory
    echo "exception: ", e.msg

suite "gittyup":
  setup:
    check init()
    let
      tmpdir = getTempDir() / "gittyup-" & $getCurrentProcessId() / ""
    tmpdir.cleanup
    let
      open = openRepository(getCurrentDir())
    check open.isOk
    var repo = open.get
    #checkpoint code.dumpError
    #check false

  teardown:
    free repo
    check shutdown()
    tmpdir.cleanup

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

  when tagging:
    test "create and delete a tag":
      block:
        thing := repo.lookupThing "HEAD":
          checkpoint code.dumpError
          check false
          break
        oid := thing.tagCreate "test":
          checkpoint code.dumpError
          check false
          break
        check repo.tagDelete("test") == grcOk

  when tagtable:
    test "tag table":
      block:
        tags := repo.tagTable:
          checkpoint code.dumpError
          check false
          break
        if "test" in tags:
          check repo.tagDelete("test") == grcOk
        check $tags["1.0.2"].oid == v102

  when specing:
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
        proc dump(things: var seq[GitThing]): string =
          for n in things.items:
            result &= $n & "\n"
        for thing in cloned.commitsForSpec(@[dotnimble]):
          echo "thing arrived"
          check thing.isOk
          if thing.isOk:
            echo "adding...", thing.get
            when specing:
              things.add thing.get
              echo "added; now have ", things.len, " things: ", thing.get
              echo things.dump
        when specing:
          echo "NOW WE FREE"
          check things.len > 10
          block found:
            for thing in things.items:
              if $thing.oid == v102:
                break found
              free thing
            check false
