version = "2.4.3"
author = "disruptek"
description = "higher-level git bindings that build upon nimgit2"
license = "MIT"
requires "nim >= 1.0.4"
requires "nimgit2 0.1.1"
requires "https://github.com/disruptek/badresults < 2.0.0"

proc execCmd(cmd: string) =
  echo "execCmd:" & cmd
  exec cmd

proc execTest(test: string) =
  execCmd "nim c   -d:git2Git -d:git2SetVer=\"v1.0.0\"             -r " & test
  execCmd "nim c   -d:git2Git -d:git2SetVer=\"v1.0.0\"  -d:release -r " & test
  execCmd "nim c   -d:git2Git -d:git2SetVer=\"v1.0.0\"  -d:danger  -r " & test
  #execCmd "nim cpp -d:git2Git -d:git2SetVer=\"v1.0.0\"  -d:danger  -r " & test
  when NimMajor >= 1 and NimMinor >= 1:
    execCmd "nim c   -d:git2Git -d:git2SetVer=\"v1.0.0\" --gc:arc -r " & test
    execCmd "nim c   -d:git2Git -d:git2SetVer=\"v1.0.0\" -d:danger --gc:arc -r " & test
    execCmd "nim c   -d:git2Static -d:git2SetVer=\"v1.0.0\" -d:danger --gc:arc -f " & test


task test, "run tests for travis":
  execTest("tests/tgit.nim")
