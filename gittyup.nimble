version = "2.4.2"
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
  execCmd "nim cpp   -d:git2Git -d:git2SetVer=\"master\"             -r " & test
  execCmd "nim cpp   -d:git2Git -d:git2SetVer=\"master\"  -d:release -r " & test
  execCmd "nim cpp   -d:git2Git -d:git2SetVer=\"master\"  -d:danger  -r " & test
  #execCmd "nim cpp -d:git2Git -d:git2SetVer=\"master\"  -d:danger  -r " & test
  when NimMajor >= 1 and NimMinor >= 1:
    execCmd "nim cpp   -d:git2Git -d:git2SetVer=\"master\" --gc:arc -r " & test


task test, "run tests for travis":
  execTest("tests/tgit.nim")
