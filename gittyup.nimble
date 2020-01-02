version = "1.0.5"
author = "disruptek"
description = "higher-level git bindings that build upon nimgit2"
license = "MIT"
requires "nim >= 1.0.4"
requires "nimgit2 0.1.1"
requires "result"

proc execCmd(cmd: string) =
  echo "execCmd:" & cmd
  exec cmd

proc execTest(test: string) =
  execCmd "nim c   -d:git2DL  -d:git2SetVer=\"0.28.4\"          -f -r " & test
  execCmd "nim c   -d:git2Git -d:git2SetVer=\"v0.28.4\"         -f -r " & test
  execCmd "nim c   -d:git2Git -d:git2SetVer=\"master\"          -f -r " & test
  execCmd "nim c   -d:git2Git -d:git2SetVer=\"master\"  -d:release -r " & test
  execCmd "nim c   -d:git2Git -d:git2SetVer=\"master\"  -d:danger  -r " & test
  execCmd "nim cpp -d:git2Git -d:git2SetVer=\"master\"  -d:danger  -r " & test
  when NimMajor >= 1 and NimMinor >= 1:
    execCmd "nim c   -d:git2Git -d:git2SetVer=\"master\" --gc:arc -r " & test
    execCmd "nim cpp -d:git2Git -d:git2SetVer=\"master\" --gc:arc -r " & test


task test, "run tests for travis":
  execTest("tests/tgit.nim")
