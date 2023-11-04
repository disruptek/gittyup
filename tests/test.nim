import std/strutils
import std/uri
import std/tables
import std/os

import gittyup except gitTrap
import balls except test

const
  v1 = "555d5d803f1c63f3fad296ba844cd6f718861d0e"
  v102 = "372deb094fb11e56171e5c9785bd316577724f2e"
  v218 = "c245dde54a6ae6a35a914337e7303769af121f01"
  cloneme = parseURI"https://github.com/disruptek/gittyup"

proc cleanup(directory: string) =
  ## obliterate a temporary directory
  try:
    removeDir directory
    check not dirExists directory
  except OSError as e:
    echo "error removing ", directory
    echo "exception: ", e.msg

let tmpdir = getTempDir() / "gittyup-" & $getCurrentProcessId() / ""

template setup(): GitRepository =
  ## setup a repo for a test
  check init() > 0
  cleanup tmpdir
  let open = repositoryOpen getCurrentDir()
  check open.isOk
  get open

template teardown() {.dirty.} =
  ## tear down a test repo
  free repo
  check shutdown() == 0
  cleanup tmpdir

template test(body: untyped) =
  ## perform a test with setup/teardown
  var repo {.inject.} = setup()
  try:
    body
  finally:
    teardown()

template gitTrap*(code: GitResultCode) =
  ## trap an api result code, use it to fail spectacularly
  if code != GIT_OK:
    fail dumpError(code)

suite "giddy up, pardner":
  ## open the local repo
  test:
    if fileExists(getEnv"HOME" / ".gitconfig"):
      # missing `shallow` subdirectory causes an error code here;
      # since we're just checking to see if we can open the repo,
      # we will merely reflect this error to the user...
      if dumpError(GIT_OK) != "":
        echo dumpError(GIT_OK)

    else:
      skip "all platforms error on missing .gitconfig"

  ## repo state
  test:
    check repo.repositoryState == GIT_REPOSITORY_STATE_NONE

  ## get the head
  test:
    head := repo.repositoryHead:
      fail dumpError(code)
    let oid = head.oid
    check $oid != ""

  ## get a thing for 2.1.8
  test:
    thing := repo.lookupThing("2.1.8"):
      fail dumpError(code)
    check $thing.oid == v218

  ## remote lookup
  test:
    origin := repo.remoteLookup("origin"):
      fail dumpError(code)
    check "gittyup" in origin.url.path

  ## clone ourselves
  test:
    cloned := clone(cloneme, tmpdir):
      fail dumpError(code)
    check GIT_REPOSITORY_STATE_NONE == repositoryState cloned

  ## create and delete a tag
  test:
    thing := repo.lookupThing "HEAD":
      fail dumpError(code)
    oid := thing.tagCreate "test":
      fail dumpError(code)
    check repo.tagDelete("test") == GIT_OK
    check repo.tagDelete("test") == GIT_ENOTFOUND

  ## tag table
  test:
    tags := repo.tagTable:
      fail dumpError(code)
    if "test" in tags:
      check repo.tagDelete("test") == GIT_OK
    else:
      when false:
        for s, tag in tags.pairs:
          echo s, " -> ", tag.oid
      ## no test tag in the table
    check "1.0.2" in tags
    check $tags["1.0.2"].oid == v102

  ## revision walk
  test:
    # clone ourselves into tmpdir
    cloned := cloneme.clone(tmpdir):
      fail dumpError(code)
    check GIT_REPOSITORY_STATE_NONE == cloned.repositoryState

    # we'll need a walker, and we'll want it freed
    walker := cloned.newRevWalk:
      fail dumpError(code)

    # find the head
    head := cloned.getHeadOid:
      fail dumpError(code)

    # start at the head
    gitTrap walker.push(head)

    # perform the walk
    for rev in cloned.revWalk(walker):
      check rev.isOk
      free rev.get

  ## commits for spec
  test:
    cloned := cloneme.clone(tmpdir):
      fail dumpError(code)
    check GIT_REPOSITORY_STATE_NONE == cloned.repositoryState
    let
      dotnimble = "gittyup.nim"

    var
      things: seq[GitThing] = @[]
    defer:
      while things.len > 0:
        free things.pop

    proc dump(things: var seq[GitThing]): string =
      for n in things.items:
        if n != nil:
          result &= $n & "\n"

    for thing in cloned.commitsForSpec(@[dotnimble]):
      check thing.isOk
      things.add thing.get

    check things.len > 10
    block found:
      for thing in things.items:
        if $thing.oid == v102:
          break found
      fail "unable to find v102"

  ## fetchRemote
  test:
    cloned := cloneme.clone(tmpdir):
      fail dumpError(code)
    check GIT_REPOSITORY_STATE_NONE == cloned.repositoryState
    check cloned.fetchRemote("origin") == GIT_OK

