version = "2.5.4"
author = "disruptek"
description = "higher-level git bindings that build upon nimgit2"
license = "MIT"
requires "nim >= 1.0.4"
requires "nimgit2 >= 0.3.1 & < 1.0.0"
requires "nimterop < 1.0.0"
requires "https://github.com/disruptek/badresults < 2.0.0"

# fix poor nimble behavior
requires "regex >= 0.15.0"

proc execCmd(cmd: string) =
  echo "execCmd:" & cmd
  exec cmd

proc execTest(test: string) =
  execCmd "nim c   -d:git2Git -d:git2SetVer=\"v1.0.1\"             -r " & test
  execCmd "nim c   -d:git2Git -d:git2SetVer=\"v1.0.1\"  -d:release -r " & test
  execCmd "nim c   -d:git2Git -d:git2SetVer=\"v1.0.1\"  -d:danger  -r " & test
  #execCmd "nim cpp -d:git2Git -d:git2SetVer=\"v1.0.0\"  -d:danger  -r " & test
  when (NimMajor, NimMinor) >= (1, 1):
    execCmd "nim c   -d:git2Git -d:git2SetVer=\"v1.0.1\" --gc:arc -r " & test
    execCmd "nim c   -d:git2Git -d:git2SetVer=\"v1.0.1\" -d:danger --gc:arc -r " & test
    execCmd "nim c   -d:git2Static -d:git2Git -d:git2SetVer=\"v1.0.1\" -d:danger --gc:arc -f " & test


task test, "run tests for travis":
  execTest("tests/tgit.nim")
