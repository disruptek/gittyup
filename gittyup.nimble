version = "2.5.5"
author = "disruptek"
description = "higher-level libgit2 bindings that build upon nimgit2"
license = "MIT"
requires "nim >= 1.0.4"
requires "nimgit2 >= 0.3.1 & < 0.4.0"
requires "https://github.com/disruptek/badresults < 2.0.0"

# impose a limit on nimterop
requires "nimterop >= 0.6.12"

# fix poor nimble behavior
requires "regex >= 0.15.0"

proc execCmd(cmd: string) =
  echo "execCmd:" & cmd
  exec cmd

proc execTest(test: string) =
  when getEnv("GITHUB_ACTIONS", "false") != "true":
    execCmd "nim c   -d:git2Git -d:git2SetVer=\"v1.0.1\"             -r " & test
    execCmd "nim c   -d:git2JBB -d:git2SetVer=\"1.0.1\"  -d:danger  -r " & test
  else:
    execCmd "nim c   -d:git2Git -d:git2SetVer=\"v1.0.1\"             -r " & test
    execCmd "nim c   -d:git2JBB -d:git2SetVer=\"1.0.1\"  -d:danger  -r " & test
    execCmd "nim c   -d:git2Static -d:git2Git -d:git2SetVer=\"v1.0.1\"  -d:danger  -r " & test
    execCmd "nim cpp -d:git2Git -d:git2SetVer=\"v1.0.1\"             -r " & test
    execCmd "nim cpp -d:git2JBB -d:git2SetVer=\"1.0.1\"  -d:danger  -r " & test
    execCmd "nim cpp -d:git2Static -d:git2Git -d:git2SetVer=\"v1.0.1\"  -d:danger  -r " & test
    when (NimMajor, NimMinor) >= (1, 2):
      execCmd "nim c   -d:git2Git -d:git2SetVer=\"v1.0.1\" --gc:arc -r " & test
      execCmd "nim c   -d:git2JBB -d:git2SetVer=\"1.0.1\" -d:danger --gc:arc -r " & test
      execCmd "nim c   -d:git2Static -d:git2Git -d:git2SetVer=\"v1.0.1\" -d:danger --gc:arc -f " & test
      execCmd "nim cpp -d:git2Git -d:git2SetVer=\"v1.0.1\" --gc:arc -r -f " & test
      execCmd "nim cpp -d:git2JBB -d:git2SetVer=\"1.0.1\" -d:danger --gc:arc -r -f " & test
      execCmd "nim cpp -d:git2Static -d:git2Git -d:git2SetVer=\"v1.0.1\" -d:danger --gc:arc -r -f " & test

task test, "run tests for ci":
  execTest("tests/tgit.nim")
