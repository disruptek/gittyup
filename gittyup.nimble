version = "2.7.0"
author = "disruptek"
description = "higher-level libgit2 bindings that build upon nimgit2"
license = "MIT"

requires "https://github.com/disruptek/badresults >= 2.0.0 & < 3.0.0"
requires "https://github.com/haxscramper/hlibgit2 >= 0.0.1 & < 1.0.0"
#requires "nimgit2 >= 0.3.1 & < 0.4.0"

when not defined(release):
  requires "https://github.com/disruptek/balls >= 2.1.2 & < 4.0.0"

# impose a limit on nimterop; removed this because nimble doesn't
# understand that dependencies may have different versions...  🙄
#requires "nimterop <= 0.6.11"

# fix poor nimble behavior
#requires "regex >= 0.15.0"

task test, "run tests for ci":
  when defined(windows):
    exec """balls.cmd -d:git2Git -d:git2SetVer="v1.1.1""""
    #exec """balls.cmd -d:git2Git -d:git2SetVer="v1.1.1" -d:git2Static"""
  else:
    exec """balls -d:git2Git -d:git2SetVer="v1.1.1""""
    #exec """balls -d:git2Git -d:git2SetVer="v1.1.1" -d:git2Static"""
