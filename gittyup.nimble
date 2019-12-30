version = "1.0.0"
author = "disruptek"
description = "comfort for nimgit2"
license = "MIT"
requires "nim >= 1.0.4"
requires "nimgit2 >= 0.1.1"

proc execCmd(cmd: string) =
  echo "execCmd:" & cmd
  exec cmd

proc execTest(test: string) =
  execCmd "nim c -f -r " & test
  execCmd "nim cpp -r " & test

task test, "run tests for travis":
  execTest("tests/tgit.nim")
