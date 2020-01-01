import std/os
import std/unittest

import gittyup

const
  v1 = "555d5d803f1c63f3fad296ba844cd6f718861d0e"

suite "gittyup":
  setup:
    check init()
    repo := openRepository(getCurrentDir()):
      echo code.dumpError
      check false

  teardown:
    check shutdown()

  test "zero errors":
    check grcOk.dumpError == ""

  test "repo state":
    check repo.repositoryState == grsNone

  test "get the head":
    head := repo.repositoryHead:
      check false
    let
      oid = head.oid
    check $oid != ""

  test "get a thing for 1.0.0":
    thing := repo.lookupThing("1.0.0"):
      check false
    check $thing.oid == v1
