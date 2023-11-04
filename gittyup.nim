import std/macros except error
import std/math
import std/times
import std/logging
import std/sets
import std/options
import std/strformat
import std/bitops
import std/os
import std/strutils
import std/hashes
import std/tables
import std/uri

import hlibgit2/strarray
import hlibgit2/types
import hlibgit2/buffer
import hlibgit2/pathspec
import hlibgit2/diff
import hlibgit2/branch
import hlibgit2/clone
import hlibgit2/status
import hlibgit2/checkout
import hlibgit2/oid
import hlibgit2/tree
import hlibgit2/errors
import hlibgit2/common
import hlibgit2/global
import hlibgit2/commit
import hlibgit2/tag
import "hlibgit2/object"
import hlibgit2/remote
import hlibgit2/refs
import hlibgit2/repository
import hlibgit2/annotated_commit
import hlibgit2/revparse
import hlibgit2/revwalk
import hlibgit2/signature

import badresults
export badresults

const
  GIT_DIFF_OPTIONS_VERSION* = 1
  GIT_STATUS_OPTIONS_VERSION* = 1
  GIT_CLONE_OPTIONS_VERSION* = 1
  GIT_CHECKOUT_OPTIONS_VERSION* = 1
  GIT_FETCH_OPTIONS_VERSION* = 1

# git_strarray_dispose replaces git_strarray_free in >v1.0.1
when not compiles(git_strarray_dispose):
  template git_strarray_dispose(arr: ptr git_strarray) =
    git_strarray_free(arr)

type
  # separating out stuff we free via routines from libgit2
  GitHeapGits = git_repository | git_reference | git_remote | git_tag |
                git_object | git_commit | git_status_list |
                git_annotated_commit | git_tree_entry | git_revwalk | git_buf |
                git_pathspec | git_tree | git_diff | git_pathspec_match_list |
                git_branch_iterator | git_signature

  # or stuff we alloc and pass to libgit2, and then free later ourselves
  NimHeapGits = git_clone_options | git_status_options | git_checkout_options |
                git_oid | git_diff_options

  GitTreeWalkCallback* = proc (root: cstring; entry: ptr git_tree_entry;
                               payload: pointer): cint

  GitObjectKind* = git_object_t
  GitThing* = ref object
    o*: GitObject
    # we really don't have anything else to say about these just yet
    case kind*: GitObjectKind
    of GIT_OBJECT_TAG:
      discard
    of GIT_OBJECT_REF_DELTA:
      discard
    of GIT_OBJECT_TREE:
      discard
    else:
      discard

  # if it's on this list, the semantics should be pretty consistent
  GitBuf* = ptr git_buf
  GitDiff* = ptr git_diff
  GitPathSpec* = ptr git_pathspec
  GitRevWalker* = ptr git_revwalk
  GitTreeEntry* = ptr git_tree_entry
  GitTreeEntries* = seq[GitTreeEntry]
  GitObject* = ptr git_object
  GitOid* = ptr git_oid
  GitOids* = seq[GitOid]
  GitRemote* = ptr git_remote
  GitReference* = ptr git_reference
  GitRepository* = ptr git_repository
  GitStrArray* = distinct git_strarray  ## strings freed by libgit2
  GittyStrArray* = distinct git_strarray  ## strings freed by nim
  GitTag* = ptr git_tag
  GitCommit* = ptr git_commit
  GitStatus* = ptr git_status_entry
  GitStatusList* = ptr git_status_list
  GitTree* = ptr git_tree
  GitSignature* = ptr git_signature
  GitTagTable* = OrderedTableRef[string, GitThing]
  GitResult*[T] = Result[T, GitResultCode]

  GitResultCode* = git_error_code
  GitRepoState* = git_repository_state_t
  GitCheckoutNotify* = git_checkout_notify_t
  GitTreeWalkMode* = git_treewalk_mode
  GitStatusShow* = git_status_show_t
  GitStatusFlag* = git_status_t
  GitCheckoutStrategy* = git_checkout_strategy_t
  GitErrorClass* = git_error_t
  GitStatusOption* = git_status_opt_t
  GitBranchType* = git_branch_t
  GitPathSpecFlag* = git_pathspec_flag_t

export git_error_code
export git_repository_state_t
export git_checkout_notify_t
export git_treewalk_mode
export git_status_show_t
export git_status_t
export git_checkout_strategy_t
export git_error_t
export git_status_opt_t
export git_branch_t
export git_pathspec_flag_t

# these just cast some cints into appropriate enums
template grc(code: cint): GitResultCode =
  to_git_error_code(cast[c_git_error_code](code))

template grc(code: GitResultCode): GitResultCode = code
template gec(code: cint): GitErrorClass =
  to_git_error_t(cast[c_git_error_t](code))

proc hash*(gcs: GitCheckoutStrategy): Hash =
  ## too large an enum for native sets
  gcs.ord.hash

macro enumValues(e: typed): untyped =
  newNimNode(nnkCurly).add(e.getType[1][1..^1])

const
  validGitStatusFlags = enumValues(GitStatusFlag)
  validGitObjectKinds = enumValues(GitObjectKind)
  defaultCheckoutStrategy = [
    GIT_CHECKOUT_SAFE,
    GIT_CHECKOUT_RECREATE_MISSING,
    GIT_CHECKOUT_SKIP_LOCKED_DIRECTORIES,
    GIT_CHECKOUT_DONT_OVERWRITE_IGNORED,
  ].toHashSet

  commonDefaultStatusFlags = {
    GIT_STATUS_OPT_INCLUDE_UNTRACKED,
    GIT_STATUS_OPT_INCLUDE_IGNORED,
    GIT_STATUS_OPT_INCLUDE_UNMODIFIED,
    GIT_STATUS_OPT_EXCLUDE_SUBMODULES,
    GIT_STATUS_OPT_DISABLE_PATHSPEC_MATCH,
    GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX,
    GIT_STATUS_OPT_RENAMES_INDEX_TO_WORKDIR,
    GIT_STATUS_OPT_RENAMES_FROM_REWRITES,
    GIT_STATUS_OPT_UPDATE_INDEX,
    GIT_STATUS_OPT_INCLUDE_UNREADABLE,
  }

  defaultStatusFlags =
    when FileSystemCaseSensitive:
      commonDefaultStatusFlags + {GIT_STATUS_OPT_SORT_CASE_SENSITIVELY}
    else:
      commonDefaultStatusFlags + {GIT_STATUS_OPT_SORT_CASE_INSENSITIVELY}

proc dumpError*(code: GitResultCode): string =
  ## retrieves the last git error message
  let err = git_error_last()
  if not err.isNil:
    result = $gec(err.klass) & " error: " & $err.message
    when defined(gitErrorsAreFatal):
      raise Defect.newException result

template dumpError() =
  let emsg = GIT_OK.dumpError
  if emsg != "":
    error emsg

template gitFail*(code: GitResultCode; body: untyped) =
  ## a version of gitTrap that expects failure; no error messages!
  if code != GIT_OK:
    body

template gitFail*(allocd: typed; code: GitResultCode; body: untyped) =
  ## a version of gitTrap that expects failure; no error messages!
  defer:
    if code == GIT_OK:
      free(allocd)
  gitFail(code, body)

template gitTrap*(code: GitResultCode; body: untyped) =
  ## trap an api result code, dump it via logging,
  ## run the body as an error handler
  if code != GIT_OK:
    dumpError()
    body

template gitTrap*(allocd: typed; code: GitResultCode; body: untyped) =
  ## trap an api result code, dump it via logging,
  ## run the body as an error handler
  defer:
    if code == GIT_OK:
      free(allocd)
  gitTrap(code, body)

# set a result variable `self` to value/error
template ok*[T](self: var Result[T, GitResultCode]; x: T): auto =
  badresults.ok(self.Result, x)
template err*[T](self: var Result[T, GitResultCode]; x: GitResultCode): auto =
  badresults.err(self.Result, x)

# create a new result (eg. for an iterator)
template ok*[T](x: T): auto =
  #results.ok(Result[T, GitResultCode], x)
  results.ok(GitResult[T], x)
template err*[T](x: GitResultCode): auto =
  #results.err(Result[T, GitResultCode], x)
  badresults.err(Result[T, GitResultCode], x)

template `:=`*[T](v: untyped{nkIdent}; vv: Result[T, GitResultCode];
                  body: untyped): untyped =
  var vr = vv
  template v: auto {.used.} = unsafeGet(vr)
  defer:
    if isOk(vr):
      when defined(debugGit):
        debug "auto-free of " & $typeof(unsafeGet(vr))
      free(unsafeGet(vr))
  if not isOk(vr):
    var code {.used, inject.} = vr.error
    when defined(debugGit):
      debug "failure: " & $code
    body

proc normalizeUrl(uri: Uri): Uri =
  ## turn a git@github.com: url into an ssh url with username, hostname
  const
    ghPrefix = "git@github.com:"
  result = uri
  if result.scheme == "" and result.path.startsWith ghPrefix:
    result.path = result.path[ghPrefix.len .. ^1]
    result.username = "git"
    result.hostname = "github.com"
    result.scheme = "ssh"

proc loadCerts(): bool =
  # https://github.com/wildart/julia/commit/2a59c5fcb579c76715f0015784b6a0a8ebda0c0c
  var
    file = getEnv("SSL_CERT_FILE")
    dir = getEnv("SSL_CERT_DIR")
  if not fileExists(file):
    file = ""
  if not dirExists(dir):
    dir = ""
  # try to set a default for linux
  when defined(posix):
    if (file, dir) == ("", ""):
      file = "/etc/ssl/certs/ca-certificates.crt"
    if not fileExists(file):
      when defined(debugGit):
        debug "skipped loading certs"
      return true
  # this seems to be helpful for git builds on linux, at least
  if file != "" and dir == "":
    dir = parentDir file
  result = git_libgit2_opts(
             GIT_OPT_SET_SSL_CERT_LOCATIONS.cint,
             file.cstring, dir.cstring) >= 0
  # this is a little heavy-handed, but it might save someone some time
  if not result:
    dumpError()

proc init*(): int =
  ## initialize the library to prepare for git operations;
  ## returns the number of outstanding initializations.
  result = git_libgit2_init()
  if result <= 0:
    raise newException(OSError, "unable to init git")
  else:
    when defined(debugGit):
      debug "git init"
  when not defined(windows):
    # let it at least try to work if certs are not found
    discard loadCerts()

proc shutdown*(): int =
  ## decrement the initialization counter.  when the counter is zero,
  ## no outstanding resources are allocated by the underlying libgit2.
  result = git_libgit2_shutdown()
  when defined(debugGit):
    debug "git shut"

template withGit(body: untyped) =
  ## convenience to ensure git is initialized and shutdown
  if init() > 0:
    defer:
      discard shutdown()
    body

template setResultAsError(result: typed; code: cint | GitResultCode) =
  ## given a git result code, assign it to the result to indicate error;
  ## this is adaptive to different return types
  when defined(debugGit):
    debug "git said " & $grc(code)
  when result is GitResultCode:
    result = grc(code)
  elif result is GitResult:
    result.err grc(code)

template withResultOf(gitsaid: cint | GitResultCode; body: untyped) =
  ## when git said there was an error, set the result code;
  ## else, run the body
  if grc(gitsaid) == GIT_OK:
    when defined(debugGit):
      debug "git said " & $grc(gitsaid)
    body
  else:
    setResultAsError(result, gitsaid)

proc free*[T: GitHeapGits](point: ptr T) =
  ## perform a free of a git-managed pointer
  withGit:
    if point.isNil:
      when not defined(release) and not defined(danger):
        raise Defect.newException "attempt to free nil git heap object"
    else:
      when defined(debugGit):
        debug "\t~> freeing git " & $typeof(point)
      when T is git_repository:
        git_repository_free(point)
      elif T is git_reference:
        git_reference_free(point)
      elif T is git_remote:
        git_remote_free(point)
      elif T is git_tag:
        git_tag_free(point)
      elif T is git_commit:
        git_commit_free(point)
      elif T is git_object:
        git_object_free(point)
      elif T is git_tree:
        git_tree_free(point)
      elif T is git_tree_entry:
        git_tree_entry_free(point)
      elif T is git_revwalk:
        git_revwalk_free(point)
      elif T is git_status_list:
        git_status_list_free(point)
      elif T is git_annotated_commit:
        git_annotated_commit_free(point)
      elif T is git_pathspec:
        git_pathspec_free(point)
      elif T is git_pathspec_match_list:
        git_pathspec_match_list_free(point)
      elif T is git_diff:
        git_diff_free(point)
      elif T is git_buf:
        git_buf_dispose(point)
      elif T is git_branch_iterator:
        git_branch_iterator_free(point)
      elif T is git_signature:
        git_signature_free(point)
      else:
        {.error: "missing a free definition for " & $typeof(T).}
      when defined(debugGit):
        debug "\t~> freed   git " & $typeof(point)

proc free*[T: NimHeapGits](point: ptr T) =
  ## perform a free of a nim-alloced pointer to git data
  if point.isNil:
    when not defined(release) or not defined(danger):
      raise Defect.newException "attempt to free nil nim heap git object"
  else:
    when defined(debugGit):
      debug "\t~> freeing nim " & $typeof(point)
    dealloc(point)
    when defined(debugGit):
      debug "\t~> freed   nim " & $typeof(point)

proc free*(thing: sink GitThing) =
  ## free a git thing and its gitobject contents appropriately
  assert not thing.isNil
  case thing.kind:
  of GIT_OBJECT_COMMIT:
    free(cast[GitCommit](thing.o))
  of GIT_OBJECT_TREE:
    free(cast[GitTree](thing.o))
  of GIT_OBJECT_TAG:
    free(cast[GitTag](thing.o))
  of GIT_OBJECT_ANY, GIT_OBJECT_INVALID, GIT_OBJECT_BLOB,
     GIT_OBJECT_OFS_DELTA, GIT_OBJECT_REF_DELTA:
    free(cast[GitObject](thing.o))
  #disarm thing

proc free*(entries: sink GitTreeEntries) =
  ## git tree entries need a special free
  for entry in entries.items:
    free(entry)

proc free*(s: string) =
  ## for template compatability only
  discard

template addr(gstrings: GitStrArray | GittyStrArray): ptr git_strarray =
  ## convenience for passing git_strarray-like values
  (ptr git_strarray)(unsafeAddr gstrings.git_strarray)

proc free*(gstrings: var GitStrArray) =
  ## free a git_strarray allocated by libgit2
  template gstrs: git_strarray = cast[git_strarray](gstrings)
  if not gstrs.strings.isNil:
    git_strarray_dispose(addr gstrings)
    assert gstrs.strings.isNil

proc free*(gstrings: var GittyStrArray) =
  ## free a git_strarray allocated by nim
  template gstrs: git_strarray = gstrings.git_strarray
  if not gstrs.strings.isNil:
    dealloc gstrs.strings
    gstrs.strings = nil

iterator items(gstrings: GitStrArray | GittyStrArray): string =
  ## emit the members of a string array
  assert not gstrings.git_strarray.strings.isNil
  for index in 0..<gstrings.git_strarray.count:
    yield $gstrings.git_strarray.strings[index]

proc toStrArray*(values: openArray[string]): GittyStrArray =
  ## future converter (?) to nim-alloc'd string array
  template gstrs: git_strarray = result.git_strarray
  gstrs.count = values.len.cuint
  if gstrs.count > 0:
    gstrs.strings = cast[ptr cstring](allocCStringArray values)

proc toStringSeq*(gstrings: GitStrArray | GittyStrArray): seq[string] =
  ## future converter (?) from nim-or-libgit-alloc'd string arrays
  template gstrs: git_strarray = gstrings.git_strarray
  if gstrs.count > 0:
    assert not gstrs.strings.isNil
    result = cstringArrayToSeq(cast[cstringArray](gstrs.strings),
                               gstrs.count.int)

proc kind(obj: GitObject | GitCommit | GitTag): GitObjectKind =
  git_object_type(cast[GitObject](obj))

proc newThing(obj: GitObject | GitCommit | GitTag): GitThing =
  ## turn a git object into a thing
  assert not obj.isNil
  GitThing(kind: obj.kind, o: cast[GitObject](obj))

proc newThing(thing: GitThing): GitThing =
  ## turning a thing into a thing involves no change
  when false:
    # crash
    result = thing
  else:
    result = newThing(thing.o)

proc short*(oid: GitOid; size: int): GitResult[string] =
  ## shorten an oid to a string of the given length
  assert not oid.isNil
  var
    output: cstring
  withGit:
    output = cast[cstring](alloc(size + 1))
    output[size] = '\0'
    withResultOf git_oid_nfmt(output, size.uint, oid):
      result.ok $output
    dealloc output

proc url*(remote: GitRemote): Uri =
  ## retrieve the url of a remote
  assert not remote.isNil
  withGit:
    result = parseUri($git_remote_url(remote)).normalizeUrl

proc oid*(entry: GitTreeEntry): GitOid =
  ## retrieve the oid of the input
  assert not entry.isNil
  result = git_tree_entry_id(entry)
  assert not result.isNil

proc oid*(got: GitReference): GitOid =
  ## retrieve the oid of the input
  assert not got.isNil
  result = git_reference_target(got)
  assert not result.isNil

proc oid*(obj: GitObject): GitOid =
  ## retrieve the oid of the input
  assert not obj.isNil
  result = git_object_id(obj)
  assert not result.isNil

proc oid*(thing: GitThing): GitOid =
  ## retrieve the oid of the input
  assert not thing.isNil
  assert not thing.o.isNil
  result = thing.o.oid
  assert not result.isNil

proc oid*(tag: GitTag): GitOid =
  ## retrieve the oid of the input
  assert not tag.isNil
  result = git_tag_id(tag)
  assert not result.isNil

func name*(got: GitReference): string =
  ## retrieve the name of the input
  assert not got.isNil
  result = $git_reference_name(got)

func name*(entry: GitTreeEntry): string =
  ## retrieve the name of the input
  assert not entry.isNil
  result = $git_tree_entry_name(entry)

func name*(remote: GitRemote): string =
  ## retrieve the name of the input
  assert not remote.isNil
  result = $git_remote_name(remote)

func isTag*(got: GitReference): bool =
  ## true if the supplied reference is a tag
  assert not got.isNil
  result = git_reference_is_tag(got) == 1

proc flags*(status: GitStatus): set[GitStatusFlag] =
  ## produce the set of flags indicating the status of the file
  assert not status.isNil
  for flag in validGitStatusFlags.items:
    if flag.ord.uint == bitand(status.status.uint, flag.ord.uint):
      result.incl flag

proc repositoryPath*(repo: GitRepository): string =
  ## the path of the .git folder, or the repo itself if it's bare
  result = $git_repository_path(repo)

func `$`*(tags: GitTagTable): string =
  assert not tags.isNil
  result = "{poorly-rendered tagtable}"

func `$`*(ps: GitPathSpec): string =
  assert not ps.isNil
  result = "{poorly-rendered pathspec}"

func `$`*(walker: GitRevWalker): string =
  assert not walker.isNil
  result = "{poorly-rendered revwalker}"

func `$`*(remote: GitRemote): string =
  assert not remote.isNil
  result = remote.name

func `$`*(repo: GitRepository): string =
  assert not repo.isNil
  result = repositoryPath(repo)

func `$`*(buffer: git_buf): string =
  result = $cast[cstring](buffer)

func `$`*(buffer: ptr git_buf): string =
  assert not buffer.isNil
  result = $cast[cstring](buffer[])

func `$`*(annotated: ptr git_annotated_commit): string =
  assert not annotated.isNil
  result = $git_annotated_commit_ref(annotated)

func `$`*(oid: GitOid): string =
  assert not oid.isNil
  result = $git_oid_tostr_s(oid)

func `$`*(tag: GitTag): string =
  assert not tag.isNil
  let
    name = git_tag_name(tag)
  if name.isNil:
    result = $name

func `$`*(reference: GitReference): string =
  assert not reference.isNil
  if reference.isTag:
    result = reference.name
  else:
    result = $reference.oid

func `$`*(entry: GitTreeEntry): string =
  assert not entry.isNil
  result = entry.name

func `$`*(obj: GitObject): string =
  ## string representation of git object
  assert not obj.isNil
  let
    kind = obj.kind
  case kind:
  of GIT_OBJECT_INVALID:
    result = "{invalid}"
  else:
    result = $kind & "-" & $obj.git_object_id

func `$`*(commit: GitCommit): string =
  assert not commit.isNil
  result = $cast[GitObject](commit)

func `$`*(thing: GitThing): string =
  assert not thing.isNil
  assert not thing.o.isNil
  result = $thing.o

func `$`*(status: GitStatus): string =
  assert not status.isNil
  for flag in status.flags.items:
    if result != "":
      result &= ","
    result &= $flag

proc copy*(commit: GitCommit): GitResult[GitCommit] =
  ## create a copy of the commit; free it with free
  assert not commit.isNil
  var
    dupe: GitCommit
  withResultOf git_commit_dup(addr dupe, commit):
    assert not dupe.isNil
    result.ok dupe

proc copy*(thing: GitThing): GitResult[GitThing] =
  ## create a copy of the thing; free it with free
  assert not thing.isNil
  assert not thing.o.isNil
  case thing.kind:
  of GIT_OBJECT_INVALID:
    result.err GIT_EINVALID
  of GIT_OBJECT_COMMIT:
    var
      dupe: GitCommit
    withResultOf git_commit_dup(addr dupe, cast[GitCommit](thing.o)):
      result.ok newThing(dupe)
  of GIT_OBJECT_TAG:
    var
      dupe: GitTag
    withResultOf git_tag_dup(addr dupe, cast[GitTag](thing.o)):
      result.ok newThing(dupe)
  else:
    var
      dupe: GitObject
    withResultOf git_object_dup(addr dupe, cast[GitObject](thing.o)):
      result.ok newThing(dupe)

proc copy*(oid: GitOid): GitResult[GitOid] =
  ## create a copy of the oid; free it with dealloc
  assert not oid.isNil
  var
    copied = cast[GitOid](sizeof(git_oid).alloc)
  withResultOf git_oid_cpy(copied, oid):
    result.ok copied

proc branchName*(got: GitReference): string =
  ## fetch a branch name assuming the reference is a branch
  assert not got.isNil
  withGit:
    # we're going to assume that the reference name is
    # no longer than the branch_name; we're using this
    # assumption to create a name: cstring of the right
    # size so we can branc_name into it safely...
    var
      name = git_reference_name(got)
    block complete:
      gitTrap git_branch_name(addr name, got).grc:
        dumpError()
        break complete
      result = $name

proc isBranch*(got: GitReference): bool =
  ## true if the supplied reference is a branch
  assert not got.isNil
  withGit:
    result = git_reference_is_branch(got) == 1

proc owner*(thing: GitThing): GitRepository =
  ## retrieve the repository that owns this thing
  assert not thing.isNil
  assert not thing.o.isNil
  result = git_object_owner(thing.o)
  assert not result.isNil

proc owner*(commit: GitCommit): GitRepository =
  ## retrieve the repository that owns this commit
  assert not commit.isNil
  result = git_commit_owner(commit)
  assert not result.isNil

proc owner*(reference: GitReference): GitRepository =
  ## retrieve the repository that owns this reference
  assert not reference.isNil
  result = git_reference_owner(reference)
  assert not result.isNil

proc setFlags[T](flags: seq[T] | set[T] | HashSet[T]): cuint =
  for flag in flags.items:
    result = bitor(result, flag.ord.cuint).cuint

proc message*(commit: GitCommit): string =
  ## retrieve the message associated with a git commit
  assert not commit.isNil
  withGit:
    result = $git_commit_message(commit)

proc message*(tag: GitTag): string =
  ## retrieve the message associated with a git tag
  assert not tag.isNil
  withGit:
    result = $git_tag_message(tag)

proc message*(thing: GitThing): string =
  ## retrieve the message associated with a git thing
  assert not thing.isNil
  assert not thing.o.isNil
  case thing.kind:
  of GIT_OBJECT_TAG:
    result = cast[GitTag](thing.o).message
  of GIT_OBJECT_COMMIT:
    result = cast[GitCommit](thing.o).message
  else:
    raise ValueError.newException:
      "Cannot get message for git object " &
        $thing & " (kind was '" & $thing.kind & "')"

proc summary*(commit: GitCommit): string =
  ## produce a summary for a given commit
  withGit:
    assert not commit.isNil
    result = $git_commit_summary(commit)

proc summary*(thing: GitThing): string =
  ## produce a summary for a git thing
  assert not thing.isNil
  assert not thing.o.isNil
  case thing.kind:
  of GIT_OBJECT_TAG:
    result = cast[GitTag](thing.o).message
  of GIT_OBJECT_COMMIT:
    result = cast[GitCommit](thing.o).summary
  else:
    raise ValueError.newException:
      "Cannot get summary for git object " &
        $thing & " (kind was '" & $thing.kind & "')"

  result = result.strip

proc free*(table: sink GitTagTable) =
  ## free a tag table
  assert not table.isNil
  withGit:
    when defined(debugGit):
      debug "\t~> freeing nim " & $typeof(table)
    for tag, obj in table.mpairs:
      when tag is GitTag:
        tag.free
        obj.free
        disarm tag
        disarm obj
      elif tag is string:
        obj.free
        disarm obj
      elif tag is GitThing:
        let
          same = tag == obj
        tag.free
        disarm tag
        # make sure we don't free the same object twice
        if not same:
          obj.free
          disarm obj
    # working around nim-1.0 vs. nim-1.1
    when (NimMajor, NimMinor) <= (1, 1):
      var t = table
      t.clear
    else:
      table.clear
    #disarm table

proc hash*(oid: GitOid): Hash =
  ## the hash of a git oid is a function of its string representation
  assert not oid.isNil
  var h: Hash = 0
  h = h !& hash($oid)
  result = !$h

proc hash*(tag: GitTag): Hash =
  ## two tags are the same if they have the same name
  assert not tag.isNil
  var h: Hash = 0
  h = h !& hash($tag)
  result = !$h

proc hash*(thing: GitThing): Hash =
  ## two git things are unique unless they share the same oid
  assert not thing.isNil
  var h: Hash = 0
  h = h !& hash(thing.oid)
  result = !$h

proc commit*(thing: GitThing): GitCommit =
  ## turn a thing into its commit
  assert not thing.isNil and thing.kind == GIT_OBJECT_COMMIT
  result = cast[GitCommit](thing.o)
  assert not result.isNil

proc committer*(thing: GitThing): GitSignature =
  ## get the committer of a thing that's a commit
  assert not thing.isNil and thing.kind == GIT_OBJECT_COMMIT
  result = git_commit_committer(cast[GitCommit](thing.o))
  assert not result.isNil

proc author*(thing: GitThing): GitSignature =
  ## get the author of a thing that's a commit
  assert not thing.isNil and thing.kind == GIT_OBJECT_COMMIT
  result = git_commit_author(cast[GitCommit](thing.o))
  assert not result.isNil

proc clone*(uri: Uri; path: string; branch = ""): GitResult[GitRepository] =
  ## clone a repository
  withGit:
    var
      options = cast[ptr git_clone_options](sizeof(git_clone_options).alloc)
    try:
      withResultOf git_clone_options_init(options, GIT_CLONE_OPTIONS_VERSION):
        if branch != "":
          options.checkout_branch = branch
        var
          repo: GitRepository
        withResultOf git_clone(addr repo, cstring($uri), path, options):
          assert not repo.isNil
          result.ok repo
    finally:
      dealloc options

proc setHeadDetached*(repo: GitRepository; oid: GitOid): GitResultCode =
  ## detach the HEAD and point it at the given OID
  withGit:
    result = git_repository_set_head_detached(repo, oid).grc

proc setHeadDetached*(repo: GitRepository; reference: string): GitResultCode =
  ## point the repo's head at the given reference
  withGit:
    var
      oid: GitOid = cast[GitOid](sizeof(git_oid).alloc)
    try:
      withResultOf git_oid_fromstr(oid, reference):
        assert not oid.isNil
        result = repo.setHeadDetached(oid)
    finally:
      free oid

proc repositoryOpen*(path: string): GitResult[GitRepository] =
  ## open a repository by path; the repository must be freed
  withGit:
    var repo: GitRepository
    withResultOf git_repository_open(addr repo, path):
      assert not repo.isNil
      result.ok repo

proc openRepository*(path: string): GitResult[GitRepository]
  {.deprecated: "use repositoryOpen".} =
  ## alias for `repositoryOpen`
  result = repositoryOpen(path)

proc fetchRemote*(repo: GitRepository; remoteName: string; refSpecs: GittyStrArray): GitResultCode =
  ## fetch from repo at `remoteName` using provided `refSpecs`
  withGit:
    var
      fetchOpts: git_fetch_options
      remote: GitRemote
    withResultOf git_fetch_options_init(addr fetchOpts, GIT_FETCH_OPTIONS_VERSION):
      withResultOf git_remote_lookup(addr remote, repo, remoteName.cstring):
        assert not remote.isNil
        try:
          result = git_remote_fetch(remote, addr refSpecs, addr fetchOpts, "fetch").grc
        finally:
          free remote

proc fetchRemote*(repo: GitRepository; remoteName: string): GitResultCode =
  ## fetch from repo at given remoteName
  var
    refSpecs: GittyStrArray
  fetchRemote(repo, remoteName, refSpecs)

proc repositoryHead*(repo: GitRepository): GitResult[GitReference] =
  ## fetch the reference for the repository's head; the reference must be freed
  withGit:
    var
      head: GitReference
    withResultOf git_repository_head(addr head, repo):
      assert not head.isNil
      result.ok head

proc headReference*(repo: GitRepository): GitResult[GitReference] =
  ## alias for repositoryHead
  result = repositoryHead(repo)

proc getRemoteNames*(repo: GitRepository): GitResult[seq[string]] =
  ## get names of all remotes
  withGit:
    var
      list: GitStrArray
    try:
      withResultOf git_remote_list(addr list, repo):
        result.ok list.toStringSeq()
    finally:
      free list

proc fetchRemotes*(repo: GitRepository, remoteNames: seq[string]): seq[GitResultCode] =
  ## fetch from repo at given remoteNames
  withGit:
    for remoteName in remoteNames.items:
      result.add:
        fetchRemote(repo, remoteName)

proc remoteLookup*(repo: GitRepository; name: string): GitResult[GitRemote] =
  ## get the remote by name; the remote must be freed
  withGit:
    var
      remote: GitRemote
    withResultOf git_remote_lookup(addr remote, repo, name):
      assert not remote.isNil
      result.ok remote

proc remoteRename*(repo: GitRepository; prior: string;
                   next: string): GitResult[seq[string]] =
  ## rename a remote
  withGit:
    var
      problems: GitStrArray
    try:
      withResultOf git_remote_rename(addr problems, repo, prior, next):
        result.ok problems.toStringSeq()
    finally:
      free problems

proc remoteDelete*(repo: GitRepository; name: string): GitResultCode =
  ## delete a remote from the repository
  withGit:
    result = git_remote_delete(repo, name).grc

proc remoteCreate*(repo: GitRepository; name: string;
                   url: Uri): GitResult[GitRemote] =
  ## create a new remote in the repository
  withGit:
    var
      remote: GitRemote
    withResultOf git_remote_create(addr remote, repo, name.cstring, cstring($url)):
      assert not remote.isNil
      result.ok remote

proc `==`*(a, b: GitOid): bool =
  ## compare two oids using libgit2's special method
  withGit:
    if a.isNil or b.isNil:
      result = false
    elif 1 in [git_oid_is_zero(a), git_oid_is_zero(b)]:
      result = false
    else:
      result = 1 == git_oid_equal(a, b)
      # sanity
      assert result == ($a == $b)

proc targetId*(thing: GitThing): GitOid =
  ## find the target oid to which a tag points
  assert not thing.isNil
  assert not thing.o.isNil
  withGit:
    result = git_tag_target_id(cast[GitTag](thing.o))
    assert not result.isNil

proc target*(thing: GitThing): GitResult[GitThing] =
  ## find the thing to which a tag points
  assert not thing.isNil
  assert not thing.o.isNil
  withGit:
    var
      obj: GitObject
    withResultOf git_tag_target(addr obj, cast[GitTag](thing.o)):
      assert not obj.isNil
      result.ok newThing(obj)

proc tagList*(repo: GitRepository): GitResult[seq[string]] =
  ## retrieve a list of tags from the repo
  withGit:
    var
      list: GitStrArray
    withResultOf git_tag_list(addr list, repo):
      try:
        result.ok list.toStringSeq()
      finally:
        free list

proc lookupThing*(repo: GitRepository; name: string): GitResult[GitThing] =
  ## try to look some thing up in the repository with the given name
  withGit:
    var obj: GitObject
    withResultOf git_revparse_single(addr obj, repo, name):
      assert obj.kind != GIT_OBJECT_INVALID
      result.ok newThing(obj)

proc newTagTable*(size = 32): GitTagTable =
  ## instantiate a new tag table
  result = newOrderedTable[string, GitThing](size)

proc addTag(tags: var GitTagTable; name: string;
            thing: sink GitThing): GitResultCode =
  assert not thing.isNil
  assert not thing.o.isNil
  ## add a thing to the tag table, perhaps peeling it first
  # if it's not a tag, just add it to the table and move on
  if thing.kind != GIT_OBJECT_TAG:
    # no need to peel this thing
    tags[name] = move thing
    result = GIT_OK
  else:
    # it's a tag, so attempt to dereference it
    var
      target = thing.target
    if target.isErr:
      # my worst fears are realized
      result = target.error
    else:
      # add the thing's target to the table under the current name
      tags[name] = move target.get
      result = GIT_OK
    # free the tag
    free thing

proc tagTable*(repo: GitRepository): GitResult[GitTagTable] =
  ## compose a table of tags and their associated references
  block complete:
    let names = repo.tagList
    # if we cannot fetch a tag list,
    if names.isErr:
      result.err names.error
      break complete

    # now we know we'll be returning a table, at least
    var
      tags = newTagTable(nextPowerOfTwo(names.get.len))

    # iterate over all the names,
    for name in names.get.items:
      # try to lookup the name
      var thing = repo.lookupThing(name)
      if thing.isErr:
        # if that failed, just continue to the next name versus error'ing
        debug &"failed lookup for `{name}`: {thing.error}"
        continue
      # peel and add the thing to the tag table
      let code = tags.addTag(name, move thing.get)
      if code != GIT_OK:
        debug &"failed peel for `{name}`: {code}"

    # don't forget to actually populate the result, i mean, who would be
    # so stupid as to not actually return the result?  and then cut a new
    # release?  like, a major release, even.  with no tests, or anything.
    result.ok tags

proc shortestTag*(table: GitTagTable; oid: string): string =
  ## pick the shortest tag that matches the oid supplied
  for name, thing in table.pairs:
    if $thing.oid == oid:
      if result == "" or name.len < result.len:
        result = name
  if result == "":
    result = oid

proc getHeadOid*(repo: GitRepository): GitResult[GitOid] =
  ## try to retrieve the #head oid from a repository
  withGit:
    block complete:
      # free the head after we're done with it
      head := repo.headReference:
        result.err code
        break complete
      # return a copy of the oid so we can free the head
      result = head.oid.copy

proc repositoryState*(repository: GitRepository): GitRepoState =
  ## fetch the state of a repository
  withGit:
    result = cast[GitRepoState](git_repository_state(repository))

iterator status*(repository: GitRepository; show: GitStatusShow;
                 flags = defaultStatusFlags): GitResult[GitStatus] =
  ## iterate over files in the repo using the given search flags
  withGit:
    var
      options = cast[ptr git_status_options](sizeof(git_status_options).alloc)
    try:

      block complete:
        var
          code = git_status_options_init(options,
                                        GIT_STATUS_OPTIONS_VERSION).grc
        if code != GIT_OK:
          # throw the error code
          yield Result[GitStatus, GitResultCode].err(code)
          break complete

        # add the options specified by the user
        options.show = show.to_c_git_status_show_t
        for flag in flags.items:
          options.flags = bitand(options.flags.uint, flag.ord.uint).cuint

        # create a new iterator
        var
          statum: GitStatusList
        code = git_status_list_new(addr statum, repository, options).grc
        if code != GIT_OK:
          # throw the error code
          yield Result[GitStatus, GitResultCode].err(code)
          break complete
        try:
          # iterate over the status list by entry index
          for index in 0 ..< git_status_list_entrycount(statum):
            # and yield a status object result per each
            yield Result[GitStatus, GitResultCode].ok git_status_byindex(statum, index.cuint)
            #yield ok[GitStatus](git_status_byindex(statum, index.cuint))
        finally:
          statum.free
    finally:
      dealloc options

proc checkoutTree*(repo: GitRepository; thing: GitThing;
                   paths: seq[string] = @[];
                   strategy = defaultCheckoutStrategy): GitResultCode =
  ## checkout a repository using a thing; supply paths to
  ## limit the checkout to, uh, those particular paths
  withGit:
    var
      options = cast[ptr git_checkout_options](sizeof(git_checkout_options).alloc)
      commit: ptr git_commit
      target: ptr git_annotated_commit
    defer:
      dealloc options

    block complete:
      # start with converting the thing to an annotated commit
      result = git_annotated_commit_lookup(addr target, repo, thing.oid).grc
      if result != GIT_OK:
        break complete
      defer:
        free target

      # use the oid of this target to look up the commit
      let oid = git_annotated_commit_id(target)
      result = git_commit_lookup(addr commit, repo, oid).grc
      if result != GIT_OK:
        break complete
      defer:
        free commit

      # setup our checkout options
      result = git_checkout_options_init(options,
                                         GIT_CHECKOUT_OPTIONS_VERSION).grc
      if result != GIT_OK:
        break complete

      # reset the strategy per flags
      options.checkout_strategy = setFlags(strategy)

      # add any supplied paths or globs; blow away anything in options
      options.paths = paths.toStrArray().git_strarray
      defer:
        free options.paths.GittyStrArray

      # checkout the tree using the commit we fetched
      result = git_checkout_tree(repo, cast[GitObject](commit), options).grc
      if result != GIT_OK:
        break complete

      # get the commit ref name
      let name = git_annotated_commit_ref(target)
      if name.isNil:
        result = git_repository_set_head_detached_from_annotated(repo, target).grc
      else:
        result = git_repository_set_head(repo, name).grc

proc checkoutTree*(repo: GitRepository; reference: string;
                   paths: seq[string] = @[];
                   strategy = defaultCheckoutStrategy): GitResultCode =
  ## checkout a repository using a reference string; supply paths to
  ## limit the checkout to, uh, those particular paths
  withGit:
    block complete:
      thing := repo.lookupThing(reference):
        setResultAsError(result, code)
        break complete
      result = repo.checkoutTree(thing, paths = paths, strategy = strategy)

proc checkoutHead*(repo: GitRepository;
                   strategy = defaultCheckoutStrategy): GitResultCode =
  ## checkout a repository's head
  withGit:
    var
      options = cast[ptr git_checkout_options](sizeof(git_checkout_options).alloc)
    try:
      # setup our checkout options
      withResultOf git_checkout_options_init(
        options, GIT_CHECKOUT_OPTIONS_VERSION):
        # reset the strategy per flags
        options.checkout_strategy = setFlags(strategy)

        # checkout the head
        result = git_checkout_head(repo, options).grc
    finally:
      dealloc options

proc setHead*(repo: GitRepository; short: string): GitResultCode =
  ## set the head of a repository
  withGit:
    result = git_repository_set_head(repo, short.cstring).grc

proc referenceDWIM*(repo: GitRepository;
                    short: string): GitResult[GitReference] =
  ## turn a string into a reference
  withGit:
    var
      refer: GitReference
    withResultOf git_reference_dwim(addr refer, repo, short):
      assert not refer.isNil
      result.ok refer

proc lookupTreeThing*(repo: GitRepository; path = "HEAD"): GitResult[GitThing] =
  ## convenience to lookup a thing with a tree type filter
  result = repo.lookupThing(path & "^{tree}")

proc treeEntryByPath*(thing: GitThing; path: string): GitResult[GitTreeEntry] =
  ## get a tree entry using its path and that of the repo
  withGit:
    var
      leaf: GitTreeEntry
    # get the entry by path using the thing as a tree
    withResultOf git_tree_entry_bypath(addr leaf,
                                       cast[GitTree](thing.o), path):
      try:
        # if it's okay, we have to make a copy of it that the user can free,
        # because when our thing is freed, it will invalidate the leaf var.
        var
          entry: GitTreeEntry
        withResultOf git_tree_entry_dup(addr entry, leaf):
          assert not entry.isNil
          result.ok entry
      finally:
        free leaf

proc treeEntryToThing*(repo: GitRepository;
                       entry: GitTreeEntry): GitResult[GitThing] =
  ## convert a tree entry into a thing
  withGit:
    var
      obj: GitObject
    withResultOf git_tree_entry_to_object(addr obj, repo, entry):
      assert not obj.isNil
      result.ok newThing(obj)

proc treeWalk*(tree: GitTree; mode: git_treewalk_mode; callback: git_treewalk_cb;
               payload: pointer): git_error_code =
  ## walk a tree and run a callback on every entry
  withGit:
    result = git_tree_walk(tree, to_c_git_treewalk_mode(mode), callback, payload).grc

proc treeWalk*(tree: GitTree; mode: git_treewalk_mode): GitResult[GitTreeEntries] =
  ## try to walk a tree and return a sequence of its entries
  withGit:
    var
      entries: GitTreeEntries

    proc walk(root: cstring; entry: ptr git_tree_entry;
               payload: pointer): cint {.exportc.} =
      # a good way to get a round; return !0 to stop iteration
      var
        dupe: GitTreeEntry
      withResultOf git_tree_entry_dup(addr dupe, entry):
        assert not dupe.isNil
        cast[var GitTreeEntries](payload).add dupe

    withResultOf tree.treeWalk(mode, cast[git_treewalk_cb](walk),
                               payload = addr entries):
      result.ok entries

proc treeWalk*(tree: GitThing;
               mode = GIT_TREEWALK_PRE): GitResult[GitTreeEntries] =
  ## the laziest way to walk a tree, ever
  result = treeWalk(cast[GitTree](tree.o), mode)

proc newRevWalk*(repo: GitRepository): GitResult[GitRevWalker] =
  ## instantiate a new walker
  withGit:
    var
      walker: GitRevWalker
    withResultOf git_revwalk_new(addr walker, repo):
      assert not walker.isNil
      result.ok walker

proc next*(walker: GitRevWalker): GitResult[GitOid] =
  ## try to get the next oid that we should walk to
  withGit:
    block complete:
      var
        oid: GitOid = cast[GitOid](sizeof(git_oid).alloc)
      withResultOf git_revwalk_next(oid, walker):
        assert not oid.isNil
        result.ok oid
        break complete
      # free the oid if we couldn't use it
      free oid

proc push*(walker: GitRevWalker; oid: GitOid): GitResultCode =
  ## add a starting oid for the walker to begin at
  withGit:
    block complete:
      pushee := copy(oid):
        setResultAsError(result, code)
        break complete
      result = git_revwalk_push(walker, pushee).grc

proc lookupCommit*(repo: GitRepository; oid: GitOid): GitResult[GitThing] =
  ## try to look a commit up in the repository with the given name
  withGit:
    var
      commit: GitCommit
    withResultOf git_commit_lookup(addr commit, repo, oid):
      assert not commit.isNil
      result.ok newThing(commit)

iterator revWalk*(repo: GitRepository;
                  walker: GitRevWalker): GitResult[GitThing] =
  ## sic the walker on a repo starting with the given oid
  withGit:
    block complete:
      var
        future = walker.next
        oid: GitOid

      # if oid won't be populated, we'll break here
      # so we don't end up trying to free it below
      if future.isErr:
        if future.error != GIT_ENOTFOUND:
          yield err[GitThing](future.error)
        break complete

      while future.isOk:
        # the future holds the next step in the walk
        oid = future.get
        defer:
          free oid

        # lookup the next commit using the current oid
        var commit = repo.lookupCommit(oid)
        if commit.isErr:
          if commit.error != GIT_ENOTFOUND:
            # undefined error; emit it as such
            yield err[GitThing](commit.error)
          # and then break iteration
          break

        # a successful lookup; yield the commit
        yield commit

        # fetch the next step in the walk
        future = walker.next
        if future.isErr:
          # if we didn't reach the end of iteration,
          if future.error notin {GIT_ITEROVER, GIT_ENOTFOUND}:
            # emit the error
            yield err[GitThing](future.error)

proc newPathSpec*(spec: openArray[string]): GitResult[GitPathSpec] =
  ## instantiate a new path spec from a strarray
  withGit:
    var
      ps: GitPathSpec
      list = spec.toStrArray()
    try:
      withResultOf git_pathspec_new(addr ps, addr list):
        assert not ps.isNil
        result.ok ps
    finally:
      free list

proc matchWithParent(commit: GitCommit; nth: cuint;
                     options: ptr git_diff_options): GitResultCode =
  ## GIT_OK if the commit's tree intersects with the nth parent's tree;
  ## else GIT_ENOTFOUND if there was no intersection
  ##
  ## (this is adapted from a helper in libgit2's log.c example)
  ## https://github.com/libgit2/libgit2/blob/master/examples/log.c
  assert not commit.isNil
  assert not options.isNil
  block complete:
    var
      repo = git_commit_owner(commit)
      parent: ptr git_commit
      pt, ct: GitTree
      diff: GitDiff

    assert not repo.isNil

    # get the nth parent
    let r1 = git_commit_parent(addr parent, commit, nth).grc
    gitTrap parent, r1:
      result = r1
      break complete

    # grab the parent's tree
    let r2 = git_commit_tree(addr pt, parent).grc
    gitTrap pt, r2:
      result = r2
      break complete

    # grab the commit's tree
    let r3 = git_commit_tree(addr ct, commit).grc
    gitTrap ct, r3:
      result = r3
      break complete

    # take a diff the the two trees
    let r4 = git_diff_tree_to_tree(addr diff, repo, pt, ct, options).grc
    gitTrap diff, r4:
      result = r4
      break complete

    result =
      case git_diff_num_deltas(diff).uint
      of 0'u:
        GIT_ENOTFOUND
      else:
        GIT_OK

proc allParentsMatch(commit: GitCommit; options: ptr git_diff_options;
                     parents: cuint): GitResult[bool] =
  assert not commit.isNil
  assert not options.isNil
  # count matching parents
  block complete:
    for nth in 0 ..< parents:
      let
        code = matchWithParent(commit, nth.cuint, options)
      case code:
      of GIT_OK:
        # this feels like a match; keep going
        discard
      of GIT_ENOTFOUND:
        # this is fine, but it's not a match
        result.ok false
        break complete
      else:
        # this is probably not that fine; error on it
        result.err code
        break complete
    # everything matched
    result.ok true

proc zeroParentsMatch(commit: GitCommit; ps: GitPathSpec): GitResult[bool] =
  ## true if this commit's tree matches the pathspec
  var
    tree: ptr git_tree
  # try to grab the commit's tree
  withResultOf git_commit_tree(addr tree, commit):
    try:
      # these don't seem worth storing...
      #var matches: ptr git_pathspec_match_list
      let
        gps: uint32 = {GIT_PATHSPEC_NO_MATCH_ERROR}.setFlags
        # match the pathspec against the tree
        code = git_pathspec_match_tree(nil, tree, gps, ps).grc
      case code:
      of GIT_OK:
        # this feels like a match
        result.ok true
      of GIT_ENOTFOUND:
        # this is fine, but it's not a match
        result.ok false
      else:
        # this is probably not that fine; error on it
        result.err code
    finally:
      free tree

proc parentsMatch(commit: GitCommit; options: ptr git_diff_options;
                  ps: GitPathSpec): GitResult[bool] =
  assert not commit.isNil
  assert not options.isNil
  assert not ps.isNil
  let
    parents: cuint = git_commit_parentcount(commit)
  if parents == 0.cuint:
    result = commit.zeroParentsMatch(ps)
  else:
    result = commit.allParentsMatch(options, parents)

iterator commitsForSpec*(repo: GitRepository;
                         spec: openArray[string]): GitResult[GitThing] =
  ## yield each commit that matches the provided pathspec
  assert not repo.isNil
  withGit:
    var
      options = cast[ptr git_diff_options](sizeof(git_diff_options).alloc)
    defer:
      dealloc options

    block complete:
      let
        code = git_diff_options_init(options, GIT_DIFF_OPTIONS_VERSION).grc
      if code != GIT_OK:
        yield err[GitThing](code)
        break complete

      options.pathspec = spec.toStrArray().git_strarray
      defer:
        free options.pathspec.GittyStrArray

      # setup a pathspec for matching against trees, and free it later
      ps := newPathSpec(spec):
        yield err[GitThing](code)
        break complete

      # we'll need a walker, and we'll want it freed
      walker := repo.newRevWalk:
        yield err[GitThing](code)
        break complete

      # find the head
      head := repo.getHeadOid:
        # no head, no problem
        break complete

      # start at the head
      gitTrap walker.push(head):
        break complete

      # iterate over ALL the commits
      # pass a copy of the head oid so revwalk can free it
      for rev in repo.revWalk(walker):
        # if there's an error, yield it
        if rev.isErr:
          #yield ok[GitThing](rev.get)
          yield Result[GitThing, GitResultCode].ok rev.get
          break complete
        else:
          let
            matched = rev.get.commit.parentsMatch(options, ps)
          if matched.isOk and matched.get:
            # all the parents matched, so yield this revision
            #yield ok[GitThing](rev.get)
            yield Result[GitThing, GitResultCode].ok rev.get
          else:
            # we're not going to emit this revision, so free it
            free rev.get
            if matched.isErr:
              # the matching process produced an error
              #yield err[GitThing](matched.error)
              yield Result[GitThing, GitResultCode].err matched.error
              break complete

proc tagCreateLightweight*(repo: GitRepository; target: GitThing;
                           name: string; force = false): GitResult[GitOid] =
  ## create a new lightweight tag in the repository
  assert not repo.isNil
  assert not target.isNil
  assert not target.o.isNil
  withGit:
    block complete:
      let
        forced: cint = if force: 1 else: 0
      var
        oid: GitOid = cast[GitOid](sizeof(git_oid).alloc)
      withResultOf git_tag_create_lightweight(oid, repo, name, target.o, forced):
        assert not oid.isNil
        result.ok oid
        break complete
      # free the oid if we didn't end up using it
      free oid

proc tagCreateLightweight*(target: GitThing; name: string;
                           force = false): GitResult[GitOid] =
  ## create a new lightweight tag in the repository
  result = tagCreateLightweight(target.owner, target, name, force = force)

proc branchUpstream*(branch: GitReference): GitResult[GitReference] =
  ## retrieve remote tracking reference for a branch reference
  withGit:
    var
      upstream: GitReference
    withResultOf git_branch_upstream(addr upstream, branch):
      assert not upstream.isNil
      result.ok upstream

proc setBranchUpstream*(branch: GitReference; name: string): GitResultCode =
  ## set the upstream for the branch to the given branch name
  assert not branch.isNil
  withGit:
    result = git_branch_set_upstream(branch, name).grc

proc branchRemoteName*(repo: GitRepository;
                       branch: string): GitResult[string] =
  ## try to fetch a single remote for a remote tracking branch
  assert not repo.isNil
  withGit:
    var
      buff: git_buf
    # "1024 bytes oughta be enough for anybody"
    withResultOf git_buf_grow(addr buff, 1024.cuint):
      try:
        withResultOf git_branch_remote_name(addr buff, repo, branch):
          result.ok $buff
      finally:
        git_buf_dispose(addr buff)

iterator branches*(repo: GitRepository;
                   flags = {GIT_BRANCH_LOCAL,
                            GIT_BRANCH_REMOTE}): GitResult[GitReference] =
  ## this time, you're just gonna have to guess at what this proc might do...
  ## (also, you're just gonna have to free your references...)
  assert not repo.isNil
  let flags =
    if GIT_BRANCH_ALL in flags:
      {GIT_BRANCH_LOCAL, GIT_BRANCH_REMOTE}
    else:
      flags
  if flags.len == 0:
    raise ValueError.newException:
      "specify set of local, remote, or all branches"

  withGit:
    let
      list = to_c_git_branch_t():
        # i know this is cookin' your noodle, but
        if GIT_BRANCH_LOCAL notin flags:
          GIT_BRANCH_REMOTE
        elif GIT_BRANCH_REMOTE notin flags:
          GIT_BRANCH_LOCAL
        else:
          GIT_BRANCH_ALL

    # follow close 'cause it's about to get weird
    block complete:
      var
        iter: ptr git_branch_iterator
        # create an iterator
        code = git_branch_iterator_new(addr iter, repo, list).grc

      # if we couldn't create the iterator,
      if code != GIT_OK:
        # then emit the error and bail
        #yield err[GitReference](code)
        yield Result[GitReference, GitResultCode].err code
        break complete
      defer:
        iter.free

      # iterate
      while true:
        var
          branch: GitReference = nil
        # depending on whether we were able to advance,
        code = git_branch_next(addr branch, unsafeAddr list, iter).grc

        case code:
        of GIT_OK:
          assert not branch.isNil
          # issue a branch result
          #yield ok(branch)
          yield Result[GitReference, GitResultCode].ok branch
        of GIT_ITEROVER:
          assert branch.isNil
          # or end iteration normally
          break complete
        else:
          assert branch.isNil
          # or end iteration with an error emission
          #yield err[GitReference](code)
          yield Result[GitReference, GitResultCode].err code
          break complete
    # now, look, i tol' you it was gonna get weird; it's
    # your own fault you weren't paying attention

proc hasThing*(tags: GitTagTable; thing: GitThing): bool =
  ## true if the thing is tagged; think hasValue() to table's hasKey()
  for commit in tags.values:
    result = commit.oid == thing.oid
    if result:
      break

proc newSignature*(name, email: string; time: Time): GitResult[GitSignature] =
  ## create a new signature using arguments; must be freed
  ## (this does not yet support the offset-in-minutes specification)
  withGit:
    var
      signature: GitSignature
    withResultOf git_signature_new(addr signature, name, email,
                                   time.toUnix.git_time_t, 0.cint):
      assert not signature.isNil
      result.ok signature

proc defaultSignature*(repo: GitRepository): GitResult[GitSignature] =
  ## create a new signature using git configuration; must be freed
  withGit:
    var
      signature: GitSignature
    withResultOf git_signature_default(addr signature, repo):
      assert not signature.isNil
      result.ok signature

proc defaultSignature*(repo: GitRepository; time: Time): GitResult[GitSignature] =
  ## create a new signature using git configuration; must be freed
  assert not repo.isNil
  let default = repo.defaultSignature
  if default.isOk:
    template sig: GitSignature = get default
    assert not sig.isNil
    try:
      result = newSignature($sig.name, $sig.email, time)
    finally:
      free sig

proc tagCreate*(repo: GitRepository; target: GitThing; name: string;
                tagger: GitSignature;
                message = ""; force = false): GitResult[GitOid] =
  ## create a new tag in the repository with signature, message
  assert not repo.isNil
  assert not target.isNil
  assert not target.o.isNil
  assert not tagger.isNil
  withGit:
    block complete:
      let
        forced: cint = if force: 1 else: 0
      var
        oid: GitOid = cast[GitOid](sizeof(git_oid).alloc)
      withResultOf git_tag_create(oid, repo, name, target.o,
                                  tagger, message, forced):
        assert git_oid_is_zero(oid) == 0
        result.ok oid
        break complete
      # free the oid if we didn't end up using it
      free oid

proc tagCreate*(repo: GitRepository; target: GitThing; name: string;
                message = ""; force = false): GitResult[GitOid] =
  ## lightweight routine to create a heavyweight signed and dated tag
  assert not repo.isNil
  assert not target.isNil
  assert not target.o.isNil
  withGit:
    let
      tagger = target.committer  # the committer, as opposed to the author
    result = repo.tagCreate(target, name, tagger,
                            message = message, force = force)

proc tagCreate*(target: GitThing; name: string;
                message = ""; force = false): GitResult[GitOid] =
  ## lightweight routine to create a heavyweight signed and dated tag
  assert not target.isNil
  assert not target.o.isNil
  withGit:
    let
      repo = target.owner        # ie. the repository that owns the target
      tagger = target.committer  # the committer, as opposed to the author
    result = repo.tagCreate(target, name, tagger,
                            message = message, force = force)

proc tagDelete*(repo: GitRepository; name: string): GitResultCode =
  ## remove a tag
  assert not repo.isNil
  withGit:
    result = git_tag_delete(repo, name).grc

proc repositoryDiscover*(path: string; ceilings: seq[string] = @[];
                         xfs = true): GitResult[string] =
  ## try to find the path of a repository in `path` or a parent; `xfs`
  ## allows cross-filesystem traversal, while `ceilings` holds stop-dirs.
  withGit:
    const
      sep = $('/') #GIT_PATH_LIST_SEPARATOR)
    var
      buff: git_buf
    # "4096 bytes oughta be enough for anybody"
    withResultOf git_buf_grow(addr buff, 4096.cuint):
      try:
        withResultOf git_repository_discover(
          addr buff, path.cstring, xfs.cint, ceilings.join(sep).cstring):

          result.ok $buff
      finally:
        git_buf_dispose(addr buff)
