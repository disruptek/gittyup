import std/os
import std/unittest

import gittyup

suite "gittyup":
  test "open/shut git":
    check init()
    check shutdown()

  test "repo state":
    check repositoryState(getCurrentDir()) == grsNone
