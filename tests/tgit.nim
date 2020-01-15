import std/tables
import std/uri
import std/strutils
import std/os
import std/unittest

import gittyup

const
  tagging = false
  tagtable = false
  specing = false
  walking = true
  v1 = "555d5d803f1c63f3fad296ba844cd6f718861d0e"
  v102 = "372deb094fb11e56171e5c9785bd316577724f2e"
  v218 = "c245dde54a6ae6a35a914337e7303769af121f01"
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

  when true:
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

    test "get a thing for 2.1.8":
      thing := repo.lookupThing("2.1.8"):
        checkpoint code.dumpError
        check false
      check $thing.oid == v218

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

  when walking:
    test "revision walk":
      block walking:
        # clone ourselves into tmpdir
        cloned := cloneme.clone(tmpdir):
          checkpoint code.dumpError
          check false
        check grsNone == cloned.repositoryState

        # we'll need a walker, and we'll want it freed
        walker := cloned.newRevWalk:
          checkpoint code.dumpError
          check false
          break walking

        # find the head
        head := cloned.getHeadOid:
          checkpoint code.dumpError
          check false
          break walking

        # start at the head
        gitTrap walker.push(head.copy):
          check false
          break walking

        for rev in cloned.revWalk(walker):
          check rev.isOk
          #echo rev.get
          #free rev.get

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
            if n != nil:
              result &= $n & "\n"
        for thing in cloned.commitsForSpec(@[dotnimble]):
          echo "thing arrived"
          check thing.isOk
          if thing.isOk:
            echo "adding...", thing.get
            things.add thing.get
        check things.len > 10
        block found:
          for thing in things.items:
            if $thing.oid == v102:
              break found
            free thing
          check false
