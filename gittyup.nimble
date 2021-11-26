version = "3.0.0"
author = "disruptek"
description = "higher-level libgit2 bindings that build upon nimgit2"
license = "MIT"

requires "https://github.com/disruptek/badresults >= 2.0.0 & < 3.0.0"
requires "https://github.com/haxscramper/hlibgit2 >= 0.1.5 & < 1.0.0"

when not defined(release):
  requires "https://github.com/disruptek/balls >= 2.1.2 & < 4.0.0"
