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

const
  git2SetVer {.strdefine, used.} = "v1.0.0"
  hasWorkingStatus* {.deprecated.} = true

when git2SetVer == "master":
  discard
elif git2SetVer == "v1.0.0":
  discard
elif not defined(debugGit):
  {.fatal: "libgit2 version `" & git2SetVer & "` unsupported".}

import nimgit2
import badresults
export badresults

# there are some name changes between the 0.28 and later versions
when compiles(git_clone_init_options):
  template git_clone_options_init(options: ptr git_clone_options;
                                  version: cint): cint =
    git_clone_init_options(options, version)

when compiles(git_checkout_init_options):
  template git_checkout_options_init(options: ptr git_checkout_options;
                                   version: cint): cint =
    git_checkout_init_options(options, version)

when compiles(git_diff_init_options):
  template git_diff_options_init(options: ptr git_diff_options;
                                   version: cint): cint =
    git_diff_init_options(options, version)

when compiles(git_status_init_options):
  template git_status_options_init(options: ptr git_status_options;
                                   version: cint): cint =
    git_status_init_options(options, version)

{.hint: "libgit2 version `" & git2SetVer & "`".}

type
  # separating out stuff we free via routines from libgit2
  GitHeapGits = git_repository | git_reference | git_remote | git_tag |
                git_strarray | git_object | git_commit | git_status_list |
                git_annotated_commit | git_tree_entry | git_revwalk | git_buf |
                git_pathspec | git_tree | git_diff | git_pathspec_match_list |
                git_branch_iterator | git_signature

  # or stuff we alloc and pass to libgit2, and then free later ourselves
  NimHeapGits = git_clone_options | git_status_options | git_checkout_options |
                git_oid | git_diff_options

  GitTreeWalkCallback* = proc (root: cstring; entry: ptr git_tree_entry;
                               payload: pointer): cint

  GitBranchType* = enum
    gbtLocal  = (GIT_BRANCH_LOCAL, "local")
    gbtRemote = (GIT_BRANCH_REMOTE, "remote")
    gbtAll    = (GIT_BRANCH_ALL, "all")

  GitTreeWalkMode* = enum
    gtwPre  = (GIT_TREEWALK_PRE, "pre")
    gtwPost = (GIT_TREEWALK_POST, "post")

  GitRepoState* = enum
    grsNone                  = (GIT_REPOSITORY_STATE_NONE,
                                "none")
    grsMerge                 = (GIT_REPOSITORY_STATE_MERGE,
                                "merge")
    grsRevert                = (GIT_REPOSITORY_STATE_REVERT,
                                "revert")
    grsRevertSequence        = (GIT_REPOSITORY_STATE_REVERT_SEQUENCE,
                                "revert sequence")
    grsCherrypick            = (GIT_REPOSITORY_STATE_CHERRYPICK,
                                "cherrypick")
    grsCherrypickSequence    = (GIT_REPOSITORY_STATE_CHERRYPICK_SEQUENCE,
                                "cherrypick sequence")
    grsBisect                = (GIT_REPOSITORY_STATE_BISECT,
                                "bisect")
    grsRebase                = (GIT_REPOSITORY_STATE_REBASE,
                                "rebase")
    grsRebaseInteractive     = (GIT_REPOSITORY_STATE_REBASE_INTERACTIVE,
                                "rebase interactive")
    grsRebaseMerge           = (GIT_REPOSITORY_STATE_REBASE_MERGE,
                                "rebase merge")
    grsApplyMailbox          = (GIT_REPOSITORY_STATE_APPLY_MAILBOX,
                                "apply mailbox")
    grsApplyMailboxOrRebase  = (GIT_REPOSITORY_STATE_APPLY_MAILBOX_OR_REBASE,
                                "apply mailbox or rebase")

  GitPathSpecFlag* = enum
    gpsDefault              = (GIT_PATHSPEC_DEFAULT, "default")
    gpsIgnoreCase           = (GIT_PATHSPEC_IGNORE_CASE, "ignore case")
    gpsUseCase              = (GIT_PATHSPEC_USE_CASE, "use case")
    gpsNoGlob               = (GIT_PATHSPEC_NO_GLOB, "no glob")
    gpsNoMatchError         = (GIT_PATHSPEC_NO_MATCH_ERROR, "no match error")
    gpsFindFailures         = (GIT_PATHSPEC_FIND_FAILURES, "find failures")
    gpsFailuresOnly         = (GIT_PATHSPEC_FAILURES_ONLY, "failures only")

  GitStatusShow* = enum
    ssIndexAndWorkdir       = (GIT_STATUS_SHOW_INDEX_AND_WORKDIR,
                               "index and workdir")
    ssIndexOnly             = (GIT_STATUS_SHOW_INDEX_ONLY,
                               "index only")
    ssWorkdirOnly           = (GIT_STATUS_SHOW_WORKDIR_ONLY,
                               "workdir only")

  GitStatusOption* = enum
    gsoIncludeUntracked      = (GIT_STATUS_OPT_INCLUDE_UNTRACKED,
                                "include untracked")
    gsoIncludeIgnored        = (GIT_STATUS_OPT_INCLUDE_IGNORED,
                                "include ignored")
    gsoIncludeUnmodified     = (GIT_STATUS_OPT_INCLUDE_UNMODIFIED,
                                "include unmodified")
    gsoExcludeSubmodules     = (GIT_STATUS_OPT_EXCLUDE_SUBMODULES,
                                "exclude submodules")
    gsoRecurseUntrackedDirs  = (GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS,
                                "recurse untracked dirs")
    gsoDisablePathspecMatch  = (GIT_STATUS_OPT_DISABLE_PATHSPEC_MATCH,
                                "disable pathspec match")
    gsoRecurseIgnoredDirs    = (GIT_STATUS_OPT_RECURSE_IGNORED_DIRS,
                                "recurse ignored dirs")
    gsoRenamesHeadToIndex    = (GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX,
                                "renames head to index")
    gsoRenamesIndexToWorkdir = (GIT_STATUS_OPT_RENAMES_INDEX_TO_WORKDIR,
                                "renames index to workdir")
    gsoSortCaseSensitively   = (GIT_STATUS_OPT_SORT_CASE_SENSITIVELY,
                                "sort case sensitively")
    gsoSortCaseInsensitively = (GIT_STATUS_OPT_SORT_CASE_INSENSITIVELY,
                                "sort case insensitively")
    gsoRenamesFromRewrites   = (GIT_STATUS_OPT_RENAMES_FROM_REWRITES,
                                "renames from rewrites")
    gsoNoRefresh             = (GIT_STATUS_OPT_NO_REFRESH,
                                "no refresh")
    gsoUpdateIndex           = (GIT_STATUS_OPT_UPDATE_INDEX,
                                "update index")
    gsoIncludeUnreadable     = (GIT_STATUS_OPT_INCLUDE_UNREADABLE,
                                "include unreadable")

  GitStatusFlag* = enum
    gsfCurrent           = (GIT_STATUS_CURRENT, "current")
    # this space intentionally left blank
    gsfIndexNew          = (GIT_STATUS_INDEX_NEW, "index new")
    gsfIndexModified     = (GIT_STATUS_INDEX_MODIFIED, "index modified")
    gsfIndexDeleted      = (GIT_STATUS_INDEX_DELETED, "index deleted")
    gsfIndexRenamed      = (GIT_STATUS_INDEX_RENAMED, "index renamed")
    gsfIndexTypechange   = (GIT_STATUS_INDEX_TYPECHANGE, "index typechange")
    # this space intentionally left blank
    gsfTreeNew           = (GIT_STATUS_WT_NEW, "tree new")
    gsfTreeModified      = (GIT_STATUS_WT_MODIFIED, "tree modified")
    gsfTreeDeleted       = (GIT_STATUS_WT_DELETED, "tree deleted")
    gsfTreeTypechange    = (GIT_STATUS_WT_TYPECHANGE, "tree typechange")
    gsfTreeRenamed       = (GIT_STATUS_WT_RENAMED, "tree renamed")
    # this space intentionally left blank
    gsfIgnored           = (GIT_STATUS_IGNORED, "ignored")
    gsfConflicted        = (GIT_STATUS_CONFLICTED, "conflicted")

  GitCheckoutStrategy* = enum
    gcsNone                      = (GIT_CHECKOUT_NONE,
                                    "dry run")
    gcsSafe                      = (GIT_CHECKOUT_SAFE,
                                    "safe")
    gcsForce                     = (GIT_CHECKOUT_FORCE,
                                    "force")
    gcsRecreateMissing           = (GIT_CHECKOUT_RECREATE_MISSING,
                                    "recreate missing")
    gcsAllowConflicts            = (GIT_CHECKOUT_ALLOW_CONFLICTS,
                                    "allow conflicts")
    gcsRemoveUntracked           = (GIT_CHECKOUT_REMOVE_UNTRACKED,
                                    "remove untracked")
    gcsRemoveIgnored             = (GIT_CHECKOUT_REMOVE_IGNORED,
                                    "remove ignored")
    gcsUpdateOnly                = (GIT_CHECKOUT_UPDATE_ONLY,
                                    "update only")
    gcsDontUpdateIndex           = (GIT_CHECKOUT_DONT_UPDATE_INDEX,
                                    "don't update index")
    gcsNoRefresh                 = (GIT_CHECKOUT_NO_REFRESH,
                                    "no refresh")
    gcsSkipUnmerged              = (GIT_CHECKOUT_SKIP_UNMERGED,
                                    "skip unmerged")
    gcsUseOurs                   = (GIT_CHECKOUT_USE_OURS,
                                    "use ours")
    gcsUseTheirs                 = (GIT_CHECKOUT_USE_THEIRS,
                                    "use theirs")
    gcsDisablePathspecMatch      = (GIT_CHECKOUT_DISABLE_PATHSPEC_MATCH,
                                    "disable pathspec match")
    # this space intentionally left blank
    gcsUpdateSubmodules          = (GIT_CHECKOUT_UPDATE_SUBMODULES,
                                    "update submodules")
    gcsUpdateSubmodulesIfChanged = (GIT_CHECKOUT_UPDATE_SUBMODULES_IF_CHANGED,
                                    "update submodules if changed")
    gcsSkipLockedDirectories     = (GIT_CHECKOUT_SKIP_LOCKED_DIRECTORIES,
                                    "skip locked directories")
    gcsDontOverwriteIgnored      = (GIT_CHECKOUT_DONT_OVERWRITE_IGNORED,
                                    "don't overwrite ignored")
    gcsConflictStyleMerge        = (GIT_CHECKOUT_CONFLICT_STYLE_MERGE,
                                    "conflict style merge")
    gcsConflictStyleDiff3        = (GIT_CHECKOUT_CONFLICT_STYLE_DIFF3,
                                    "conflict style diff3")
    gcsDontRemoveExisting        = (GIT_CHECKOUT_DONT_REMOVE_EXISTING,
                                    "don't remove existing")
    gcsDontWriteIndex            = (GIT_CHECKOUT_DONT_WRITE_INDEX,
                                    "don't write index")

  GitCheckoutNotify* = enum
    gcnNone            = (GIT_CHECKOUT_NOTIFY_NONE, "none")
    gcnConflict        = (GIT_CHECKOUT_NOTIFY_CONFLICT, "conflict")
    gcnDirty           = (GIT_CHECKOUT_NOTIFY_DIRTY, "dirty")
    gcnUpdated         = (GIT_CHECKOUT_NOTIFY_UPDATED, "updated")
    gcnUntracked       = (GIT_CHECKOUT_NOTIFY_UNTRACKED, "untracked")
    gcnIgnored         = (GIT_CHECKOUT_NOTIFY_IGNORED, "ignored")
    gcnAll             = (GIT_CHECKOUT_NOTIFY_ALL, "all")

  GitResultCode* = enum
    grcApplyFail       = (GIT_EAPPLYFAIL, "patch failed")
    grcIndexDirty      = (GIT_EINDEXDIRTY, "dirty index")
    grcMismatch        = (GIT_EMISMATCH, "hash mismatch")
    grcRetry           = (GIT_RETRY, "retry")
    grcIterOver        = (GIT_ITEROVER, "end of iteration")
    grcPassThrough     = (GIT_PASSTHROUGH, "pass-through")
    # this space intentionally left blank
    grcMergeConflict   = (GIT_EMERGE_CONFLICT, "merge conflict")
    grcDirectory       = (GIT_EDIRECTORY, "directory")
    grcUncommitted     = (GIT_EUNCOMMITTED, "uncommitted")
    grcInvalid         = (GIT_EINVALID, "invalid")
    grcEndOfFile       = (GIT_EEOF, "end-of-file")
    grcPeel            = (GIT_EPEEL, "peel")
    grcApplied         = (GIT_EAPPLIED, "applied")
    grcCertificate     = (GIT_ECERTIFICATE, "certificate")
    grcAuthentication  = (GIT_EAUTH, "authentication")
    grcModified        = (GIT_EMODIFIED, "modified")
    grcLocked          = (GIT_ELOCKED, "locked")
    grcConflict        = (GIT_ECONFLICT, "conflict")
    grcInvalidSpec     = (GIT_EINVALIDSPEC, "invalid spec")
    grcNonFastForward  = (GIT_ENONFASTFORWARD, "not fast-forward")
    grcUnmerged        = (GIT_EUNMERGED, "unmerged")
    grcUnbornBranch    = (GIT_EUNBORNBRANCH, "unborn branch")
    grcBareRepo        = (GIT_EBAREREPO, "bare repository")
    grcUser            = (GIT_EUSER, "user-specified")
    grcBuffer          = (GIT_EBUFS, "buffer overflow")
    grcAmbiguous       = (GIT_EAMBIGUOUS, "ambiguous match")
    grcExists          = (GIT_EEXISTS, "object exists")
    grcNotFound        = (GIT_ENOTFOUND, "not found")
    # this space intentionally left blank
    grcError           = (GIT_ERROR, "generic error")
    grcOk              = (GIT_OK, "ok")

  GitErrorClass* = enum
    gecNone        = (GIT_ERROR_NONE, "none")
    gecNoMemory    = (GIT_ERROR_NOMEMORY, "no memory")
    gecOS          = (GIT_ERROR_OS, "os")
    gecInvalid     = (GIT_ERROR_INVALID, "invalid")
    gecReference   = (GIT_ERROR_REFERENCE, "reference")
    gecZlib        = (GIT_ERROR_ZLIB, "zlib")
    gecRepository  = (GIT_ERROR_REPOSITORY, "repository")
    gecConfig      = (GIT_ERROR_CONFIG, "config")
    gecRegEx       = (GIT_ERROR_REGEX, "regex")
    gecODB         = (GIT_ERROR_ODB, "odb")
    gecIndex       = (GIT_ERROR_INDEX, "index")
    gecObject      = (GIT_ERROR_OBJECT, "object")
    gecNet         = (GIT_ERROR_NET, "network")
    gecTag         = (GIT_ERROR_TAG, "tag")
    gecTree        = (GIT_ERROR_TREE, "tree")
    gecIndexer     = (GIT_ERROR_INDEXER, "indexer")
    gecSSL         = (GIT_ERROR_SSL, "ssl")
    gecSubModule   = (GIT_ERROR_SUBMODULE, "submodule")
    gecThread      = (GIT_ERROR_THREAD, "thread")
    gecStash       = (GIT_ERROR_STASH, "stash")
    gecCheckOut    = (GIT_ERROR_CHECKOUT, "check out")
    gecFetchHead   = (GIT_ERROR_FETCHHEAD, "fetch head")
    gecMerge       = (GIT_ERROR_MERGE, "merge")
    gecSSH         = (GIT_ERROR_SSH, "ssh")
    gecFilter      = (GIT_ERROR_FILTER, "filter")
    gecRevert      = (GIT_ERROR_REVERT, "revert")
    gecCallBack    = (GIT_ERROR_CALLBACK, "call back")
    gecCherryPick  = (GIT_ERROR_CHERRYPICK, "cherry pick")
    gecDescribe    = (GIT_ERROR_DESCRIBE, "describe")
    gecReBase      = (GIT_ERROR_REBASE, "re-base")
    gecFileSystem  = (GIT_ERROR_FILESYSTEM, "filesystem")
    gecPatch       = (GIT_ERROR_PATCH, "patch")
    gecWorkTree    = (GIT_ERROR_WORKTREE, "work tree")
    gecSHA1        = (GIT_ERROR_SHA1, "sha1")

  GitObjectKind* = enum
    # we have to add 2 here to satisfy nim; discriminants.low must be zero
    goAny         = (2 + GIT_OBJECT_ANY, "object")        # -2
    goInvalid     = (2 + GIT_OBJECT_INVALID, "invalid")   # -1
    # this space intentionally left blank
    goCommit      = (2 + GIT_OBJECT_COMMIT, "commit")     #  1
    goTree        = (2 + GIT_OBJECT_TREE, "tree")         #  2
    goBlob        = (2 + GIT_OBJECT_BLOB, "blob")         #  3
    goTag         = (2 + GIT_OBJECT_TAG, "tag")           #  4
    # this space intentionally left blank
    goOfsDelta    = (2 + GIT_OBJECT_OFS_DELTA, "ofs")     #  6
    goRefDelta    = (2 + GIT_OBJECT_REF_DELTA, "ref")     #  7

  GitThing* = ref object
    o*: GitObject
    # we really don't have anything else to say about these just yet
    case kind*: GitObjectKind:
    of goTag:
      discard
    of goRefDelta:
      discard
    of goTree:
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
  GitStrArray* = ptr git_strarray
  GitTag* = ptr git_tag
  GitCommit* = ptr git_commit
  GitStatus* = ptr git_status_entry
  GitStatusList* = ptr git_status_list
  GitTree* = ptr git_tree
  GitSignature* = ptr git_signature

  GitTagTable* = OrderedTableRef[string, GitThing]
  GitResult*[T] = Result[T, GitResultCode]

# these just cast some cints into appropriate enums
template grc(code: cint): GitResultCode = cast[GitResultCode](code.ord)
template grc(code: GitResultCode): GitResultCode = code
template gec(code: cint): GitErrorClass = cast[GitErrorClass](code.ord)

# can't remember why we need this, but i'm curious.  let me know.
proc hash*(gcs: GitCheckoutStrategy): Hash = gcs.ord.hash

macro enumValues(e: typed): untyped =
  newNimNode(nnkCurly).add(e.getType[1][1..^1])

const
  validGitStatusFlags = enumValues(GitStatusFlag)
  validGitObjectKinds = enumValues(GitObjectKind)
  defaultCheckoutStrategy = [
    gcsSafe,
    gcsRecreateMissing,
    gcsSkipLockedDirectories,
    gcsDontOverwriteIgnored,
  ].toHashSet

  commonDefaultStatusFlags: set[GitStatusOption] = {
    gsoIncludeUntracked,
    gsoIncludeIgnored,
    gsoIncludeUnmodified,
    gsoExcludeSubmodules,
    gsoDisablePathspecMatch,
    gsoRenamesHeadToIndex,
    gsoRenamesIndexToWorkdir,
    gsoRenamesFromRewrites,
    gsoUpdateIndex,
    gsoIncludeUnreadable,
  }

  defaultStatusFlags =
    when FileSystemCaseSensitive:
      commonDefaultStatusFlags + {gsoSortCaseSensitively}
    else:
      commonDefaultStatusFlags + {gsoSortCaseInsensitively}

proc dumpError*(code: GitResultCode): string =
  let err = git_error_last()
  if err != nil:
    result = $gec(err.klass) & " error: " & $err.message
    when defined(gitErrorsAreFatal):
      raise newException(Defect, emsg)

template dumpError() =
  let emsg = grcOk.dumpError
  if emsg != "":
    error emsg

template gitFail*(code: GitResultCode; body: untyped) =
  ## a version of gitTrap that expects failure; no error messages!
  if code != grcOk:
    body

template gitFail*(allocd: typed; code: GitResultCode; body: untyped) =
  ## a version of gitTrap that expects failure; no error messages!
  defer:
    if code == grcOk:
      free(allocd)
  gitFail(code, body)

template gitTrap*(code: GitResultCode; body: untyped) =
  ## trap an api result code, dump it via logging,
  ## run the body as an error handler
  if code != grcOk:
    dumpError()
    body

template gitTrap*(allocd: typed; code: GitResultCode; body: untyped) =
  ## trap an api result code, dump it via logging,
  ## run the body as an error handler
  defer:
    if code == grcOk:
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
        echo "auto-free of ", typeof(unsafeGet(vr))
      free(unsafeGet(vr))
  if not isOk(vr):
    var code {.used, inject.} = vr.error
#    when defined(debugGit):
#      debug "failure ", $v, ": ", $code
#      echo "failure ", $v, ": ", $code
    body

proc normalizeUrl(uri: Uri): Uri =
  result = uri
  if result.scheme == "" and result.path.startsWith("git@github.com:"):
    result.path = result.path["git@github.com:".len .. ^1]
    result.username = "git"
    result.hostname = "github.com"
    result.scheme = "ssh"

proc init*(): bool =
  when defined(gitShutsDown):
    result = git_libgit2_init() > 0
    when defined(debugGit):
      debug "git init"
      echo "git init"
  else:
    block:
      once:
        result = git_libgit2_init() > 0
        when defined(debugGit):
          debug "git init"
          echo "git init"
        break
      result = true

proc shutdown*(): bool =
  when defined(gitShutsDown):
    result = git_libgit2_shutdown() >= 0
    when defined(debugGit):
      debug "git shut"
      echo "git shut"
  else:
    result = true

template withGit(body: untyped) =
  if not init():
    raise newException(OSError, "unable to init git")
  defer:
    if not shutdown():
      raise newException(OSError, "unable to shut git")
  body

template setResultAsError(result: typed; code: cint | GitResultCode) =
  when result is GitResultCode:
    result = grc(code)
  elif result is GitResult:
    result.err grc(code)

template withResultOf(gitsaid: cint | GitResultCode; body: untyped) =
  ## when git said there was an error, set the result code;
  ## else, run the body
  if grc(gitsaid) == grcOk:
    body
  else:
    setResultAsError(result, gitsaid)

proc free*[T: GitHeapGits](point: ptr T) =
  withGit:
    if point == nil:
      when not defined(release) and not defined(danger):
        raise newException(Defect, "attempt to free nil git heap object")
    else:
      when defined(debugGit):
        echo "\t~> freeing git", typeof(point)
      when T is git_repository:
        git_repository_free(point)
      elif T is git_reference:
        git_reference_free(point)
      elif T is git_remote:
        git_remote_free(point)
      elif T is git_strarray:
        git_strarray_free(point)
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
        echo "\t~> freed   git", typeof(point)

proc free*[T: NimHeapGits](point: ptr T) =
  if point == nil:
    when not defined(release) and not defined(danger):
      raise newException(Defect, "attempt to free nil nim heap git object")
  else:
    when defined(debugGit):
      echo "\t~> freeing nim", typeof(point)
    dealloc(point)
    when defined(debugGit):
      echo "\t~> freed   nim", typeof(point)

proc free*(thing: sink GitThing) =
  assert thing != nil
  withGit:
    case thing.kind:
    of goCommit:
      free(cast[GitCommit](thing.o))
    of goTree:
      free(cast[GitTree](thing.o))
    of goTag:
      free(cast[GitTag](thing.o))
    of {goAny, goInvalid, goBlob, goOfsDelta, goRefDelta}:
      free(cast[GitObject](thing.o))
    #disarm thing

proc free*(entries: sink GitTreeEntries) =
  withGit:
    for entry in entries.items:
      free(entry)

func kind(obj: GitObject): GitObjectKind =
  ## fetch the GitObjectKind of a git object
  assert obj != nil
  assert GitObjectKind.low == goAny
  result = GitObjectKind(git_object_type(obj) - GIT_OBJECT_ANY)
  if validGitObjectKinds * {result} == {}:
    result = goInvalid

proc newThing(obj: GitObject | GitCommit | GitTag): GitThing =
  ## turn a git object into a thing
  assert obj != nil
  when true:
    result = GitThing(kind: cast[GitObject](obj).kind, o: cast[GitObject](obj))
  else:
    try:
      result = GitThing(kind: cast[GitObject](obj).kind, o: cast[GitObject](obj))
    except:
      result = GitThing(kind: goAny, o: cast[GitObject](obj))

proc newThing(thing: GitThing): GitThing =
  ## turning a thing into a thing involves no change
  when false:
    # crash
    result = thing
  else:
    result = newThing(thing.o)

proc short*(oid: GitOid; size: int): GitResult[string] =
  ## shorten an oid to a string of the given length
  assert oid != nil
  var
    output: cstring
  withGit:
    output = cast[cstring](alloc(size + 1))
    output[size] = '\0'
    when git2SetVer == "master":
      withResultOf git_oid_nfmt(output, size.uint, oid):
        result.ok $output
    elif git2SetVer == "v1.0.0":
      withResultOf git_oid_nfmt(output, size.uint, oid):
        result.ok $output
    else:
      git_oid_nfmt(output, size.uint, oid)
      result.ok $output
    dealloc output

proc url*(remote: GitRemote): Uri =
  ## retrieve the url of a remote
  assert remote != nil
  withGit:
    result = parseUri($git_remote_url(remote)).normalizeUrl

proc oid*(entry: GitTreeEntry): GitOid =
  assert entry != nil
  result = git_tree_entry_id(entry)
  assert result != nil

proc oid*(got: GitReference): GitOid =
  assert got != nil
  result = git_reference_target(got)
  assert result != nil

proc oid*(obj: GitObject): GitOid =
  assert obj != nil
  result = git_object_id(obj)
  assert result != nil

proc oid*(thing: GitThing): GitOid =
  assert thing != nil and thing.o != nil
  result = thing.o.oid
  assert result != nil

proc oid*(tag: GitTag): GitOid =
  assert tag != nil
  result = git_tag_id(tag)
  assert result != nil

func name*(got: GitReference): string =
  assert got != nil
  result = $git_reference_name(got)

func name*(entry: GitTreeEntry): string =
  assert entry != nil
  result = $git_tree_entry_name(entry)

func name*(remote: GitRemote): string =
  assert remote != nil
  result = $git_remote_name(remote)

func isTag*(got: GitReference): bool =
  assert got != nil
  result = git_reference_is_tag(got) == 1

proc flags*(status: GitStatus): set[GitStatusFlag] =
  assert status != nil
  ## produce the set of flags indicating the status of the file
  for flag in validGitStatusFlags.items:
    if flag.ord.uint == bitand(status.status.uint, flag.ord.uint):
      result.incl flag

func `$`*(tags: GitTagTable): string =
  assert tags != nil
  result = "{poorly-rendered tagtable}"

func `$`*(ps: GitPathSpec): string =
  assert ps != nil
  result = "{poorly-rendered pathspec}"

func `$`*(walker: GitRevWalker): string =
  assert walker != nil
  result = "{poorly-rendered revwalker}"

func `$`*(remote: GitRemote): string =
  assert remote != nil
  result = remote.name

func `$`*(repo: GitRepository): string =
  assert repo != nil
  result = $git_repository_path(repo)

func `$`*(buffer: ptr git_buf): string =
  assert buffer != nil
  result = $cast[cstring](buffer)

func `$`*(annotated: ptr git_annotated_commit): string =
  assert annotated != nil
  result = $git_annotated_commit_ref(annotated)

func `$`*(oid: GitOid): string =
  assert oid != nil
  result = $git_oid_tostr_s(oid)

func `$`*(tag: GitTag): string =
  assert tag != nil
  let
    name = git_tag_name(tag)
  if name != nil:
    result = $name

func `$`*(reference: GitReference): string =
  assert reference != nil
  if reference.isTag:
    result = reference.name
  else:
    result = $reference.oid

func `$`*(entry: GitTreeEntry): string =
  assert entry != nil
  result = entry.name

func `$`*(obj: GitObject): string =
  ## string representation of git object
  assert obj != nil
  let
    kind = obj.kind
  case kind:
  of goInvalid:
    result = "{invalid}"
  else:
    result = $kind & "-" & $obj.git_object_id

func `$`*(commit: GitCommit): string =
  assert commit != nil
  result = $cast[GitObject](commit)

func `$`*(thing: GitThing): string =
  assert thing != nil and thing.o != nil
  result = $thing.o

func `$`*(status: GitStatus): string =
  assert status != nil
  for flag in status.flags.items:
    if result != "":
      result &= ","
    result &= $flag

proc copy*(commit: GitCommit): GitResult[GitCommit] =
  ## create a copy of the commit; free it with free
  assert commit != nil
  var
    dupe: GitCommit
  withResultOf git_commit_dup(addr dupe, commit):
    assert dupe != nil
    result.ok dupe

proc copy*(thing: GitThing): GitResult[GitThing] =
  ## create a copy of the thing; free it with free
  assert thing != nil and thing.o != nil
  case thing.kind:
  of goInvalid:
    result.err grcInvalid
  of goCommit:
    var
      dupe: GitCommit
    withResultOf git_commit_dup(addr dupe, cast[GitCommit](thing.o)):
      result.ok newThing(dupe)
  of goTag:
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
  assert oid != nil
  var
    copied = cast[GitOid](sizeof(git_oid).alloc)
  when git2SetVer == "master":
    withResultOf git_oid_cpy(copied, oid):
      result.ok copied
  elif git2SetVer == "v1.0.0":
    withResultOf git_oid_cpy(copied, oid):
      result.ok copied
  else:
    git_oid_cpy(copied, oid)
    result.ok copied
    assert copied != nil

proc branchName*(got: GitReference): string =
  ## fetch a branch name assuming the reference is a branch
  assert got != nil
  withGit:
    # we're going to assume that the reference name is
    # no longer than the branch_name; we're using this
    # assumption to create a name: cstring of the right
    # size so we can branc_name into it safely...
    var
      name = git_reference_name(got)
    block:
      gitTrap git_branch_name(addr name, got).grc:
        dumpError()
        break
      result = $name

proc isBranch*(got: GitReference): bool =
  assert got != nil
  withGit:
    result = git_reference_is_branch(got) == 1

proc owner*(thing: GitThing): GitRepository =
  ## retrieve the repository that owns this thing
  assert thing != nil and thing.o != nil
  result = git_object_owner(thing.o)
  assert result != nil

proc owner*(commit: GitCommit): GitRepository =
  ## retrieve the repository that owns this commit
  assert commit != nil
  result = git_commit_owner(commit)
  assert result != nil

proc owner*(reference: GitReference): GitRepository =
  ## retrieve the repository that owns this reference
  assert reference != nil
  result = git_reference_owner(reference)
  assert result != nil

proc setFlags[T](flags: seq[T] | set[T] | HashSet[T]): cuint =
  for flag in flags.items:
    result = bitor(result, flag.ord.cuint).cuint

proc message*(commit: GitCommit): string =
  assert commit != nil
  withGit:
    result = $git_commit_message(commit)

proc message*(tag: GitTag): string =
  assert tag != nil
  withGit:
    result = $git_tag_message(tag)

proc message*(thing: GitThing): string =
  assert thing != nil and thing.o != nil
  case thing.kind:
  of goTag:
    result = cast[GitTag](thing.o).message
  of goCommit:
    result = cast[GitCommit](thing.o).message
  else:
    raise newException(ValueError, "dunno how to get a message: " & $thing)

proc summary*(commit: GitCommit): string =
  ## produce a summary for a given commit
  withGit:
    assert commit != nil
    result = $git_commit_summary(commit)

proc summary*(thing: GitThing): string =
  assert thing != nil and thing.o != nil
  case thing.kind:
  of goTag:
    result = cast[GitTag](thing.o).message
  of goCommit:
    result = cast[GitCommit](thing.o).summary
  else:
    raise newException(ValueError, "dunno how to get a summary: " & $thing)
  result = result.strip

proc free*(table: sink GitTagTable) =
  ## free a tag table
  assert table != nil
  withGit:
    when defined(debugGit):
      echo "\t~> freeing nim", typeof(table)
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
  assert oid != nil
  var h: Hash = 0
  h = h !& hash($oid)
  result = !$h

proc hash*(tag: GitTag): Hash =
  assert tag != nil
  var h: Hash = 0
  h = h !& hash($tag)
  result = !$h

proc hash*(thing: GitThing): Hash =
  assert thing != nil
  var h: Hash = 0
  h = h !& hash($thing.oid)
  result = !$h

proc commit*(thing: GitThing): GitCommit =
  ## turn a thing into its commit
  assert thing != nil and thing.kind == goCommit
  result = cast[GitCommit](thing.o)
  assert result != nil

proc committer*(thing: GitThing): GitSignature =
  ## get the committer of a thing that's a commit
  assert thing != nil and thing.kind == goCommit
  result = git_commit_committer(cast[GitCommit](thing.o))
  assert result != nil

proc author*(thing: GitThing): GitSignature =
  ## get the author of a thing that's a commit
  assert thing != nil and thing.kind == goCommit
  result = git_commit_author(cast[GitCommit](thing.o))
  assert result != nil

proc clone*(uri: Uri; path: string; branch = ""): GitResult[GitRepository] =
  ## clone a repository
  withGit:
    var
      options = cast[ptr git_clone_options](sizeof(git_clone_options).alloc)
    defer:
      dealloc options
    withResultOf git_clone_options_init(options, GIT_CLONE_OPTIONS_VERSION):
      if branch != "":
        options.checkout_branch = branch
      var
        repo: GitRepository
      withResultOf git_clone(addr repo, $uri, path, options):
        assert repo != nil
        result.ok repo

proc setHeadDetached*(repo: GitRepository; oid: GitOid): GitResultCode =
  ## detach the HEAD and point it at the given OID
  withGit:
    result = git_repository_set_head_detached(repo, oid).grc

proc setHeadDetached*(repo: GitRepository; reference: string): GitResultCode =
  ## point the repo's head at the given reference
  withGit:
    var
      oid: GitOid = cast[GitOid](sizeof(git_oid).alloc)
    defer:
      free oid
    withResultOf git_oid_fromstr(oid, reference):
      assert oid != nil
      result = repo.setHeadDetached(oid)

proc openRepository*(path: string): GitResult[GitRepository] =
  ## open a repository by path; the repository must be freed
  withGit:
    var
      repo: GitRepository
    withResultOf git_repository_open(addr repo, path):
      assert repo != nil
      result.ok repo

proc repositoryHead*(repo: GitRepository): GitResult[GitReference] =
  ## fetch the reference for the repository's head; the reference must be freed
  withGit:
    var
      head: GitReference
    withResultOf git_repository_head(addr head, repo):
      assert head != nil
      result.ok head

proc headReference*(repo: GitRepository): GitResult[GitReference] =
  ## alias for repositoryHead
  result = repositoryHead(repo)

proc remoteLookup*(repo: GitRepository; name: string): GitResult[GitRemote] =
  ## get the remote by name; the remote must be freed
  withGit:
    var
      remote: GitRemote
    withResultOf git_remote_lookup(addr remote, repo, name):
      assert remote != nil
      result.ok remote

proc remoteRename*(repo: GitRepository; prior: string;
                   next: string): GitResult[seq[string]] =
  ## rename a remote
  withGit:
    var
      list: git_strarray
    withResultOf git_remote_rename(addr list, repo, prior, next):
      defer:
        git_strarray_free(addr list)
      if list.count == 0'u:
        result.ok newSeq[string]()
      else:
        result.ok cstringArrayToSeq(cast[cstringArray](list.strings), list.count)

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
    withResultOf git_remote_create(addr remote, repo, name, $url):
      assert remote != nil
      result.ok remote

proc `==`*(a, b: GitOid): bool =
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
  withGit:
    result = git_tag_target_id(cast[GitTag](thing.o))
    assert result != nil

proc target*(thing: GitThing): GitResult[GitThing] =
  withGit:
    var
      obj: GitObject
    withResultOf git_tag_target(addr obj, cast[GitTag](thing.o)):
      assert obj != nil
      result.ok newThing(obj)

proc tagList*(repo: GitRepository): GitResult[seq[string]] =
  ## retrieve a list of tags from the repo
  withGit:
    var
      list: git_strarray
    withResultOf git_tag_list(addr list, repo):
      defer:
        git_strarray_free(addr list)
      if list.count == 0'u:
        result.ok newSeq[string]()
      else:
        result.ok cstringArrayToSeq(cast[cstringArray](list.strings), list.count)

proc lookupThing*(repo: GitRepository; name: string): GitResult[GitThing] =
  ## try to look some thing up in the repository with the given name
  withGit:
    var
      obj: GitObject
    withResultOf git_revparse_single(addr obj, repo, name):
      result.ok newThing(obj)

proc newTagTable*(size = 32): GitTagTable =
  ## instantiate a new table
  result = newOrderedTable[string, GitThing](size)

proc addTag(tags: var GitTagTable; name: string;
            thing: var GitThing): GitResultCode =
  ## add a thing to the tag table, perhaps peeling it first
  # if it's not a tag, just add it to the table and move on
  if thing.kind != goTag:
    # no need to peel this thing
    tags.add name, thing
    result = grcOk
  else:
    # it's a tag, so attempt to dereference it
    let
      target = thing.target
    if target.isErr:
      # my worst fears are realized
      result = target.error
    else:
      # add the thing's target to the table under the current name
      tags.add name, target.get
      result = grcOk
    # free the thing; we don't need it anymore
    free thing

proc tagTable*(repo: GitRepository): GitResult[GitTagTable] =
  ## compose a table of tags and their associated references
  block:
    let
      names = repo.tagList
    # if we cannot fetch a tag list,
    if names.isErr:
      result.err names.error
      break

    # now we know we'll be returning a table, at least
    var
      tags = newTagTable(nextPowerOfTwo(names.get.len))

    # iterate over all the names,
    for name in names.get.items:
      var
        # try to lookup the name
        thing = repo.lookupThing(name)
      if thing.isErr:
        # if that failed, just continue to the next name versus error'ing
        debug &"failed lookup for `{name}`: {thing.error}"
      else:
        # peel and add the thing to the tag table
        let code = tags.addTag(name, thing.get)
        if code != grcOk:
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
    block:
      # free the head after we're done with it
      head := repo.headReference:
        result.err code
        break
      # return a copy of the oid so we can free the head
      result = head.oid.copy

proc repositoryState*(repository: GitRepository): GitRepoState =
  ## fetch the state of a repository
  withGit:
    result = cast[GitRepoState](git_repository_state(repository))

when hasWorkingStatus == true:
  iterator status*(repository: GitRepository; show: GitStatusShow;
                   flags = defaultStatusFlags): GitResult[GitStatus] =
    ## iterate over files in the repo using the given search flags
    withGit:
      var
        options = cast[ptr git_status_options](sizeof(git_status_options).alloc)
      defer:
        dealloc options

      block:
        var
          code = git_status_options_init(options, GIT_STATUS_OPTIONS_VERSION).grc
        if code != grcOk:
          # throw the error code
          yield Result[GitStatus, GitResultCode].err(code)
          break

        # add the options specified by the user
        options.show = cast[git_status_show_t](show)
        for flag in flags.items:
          options.flags = bitand(options.flags.uint, flag.ord.uint).cuint

        # create a new iterator
        var
          statum: GitStatusList
        code = git_status_list_new(addr statum, repository, options).grc
        if code != grcOk:
          # throw the error code
          yield Result[GitStatus, GitResultCode].err(code)
          break
        # remember to free it
        defer:
          statum.free

        # iterate over the status list by entry index
        for index in 0 ..< git_status_list_entrycount(statum):
          # and yield a status object result per each
          yield Result[GitStatus, GitResultCode].ok git_status_byindex(statum, index.cuint)
          #yield ok[GitStatus](git_status_byindex(statum, index.cuint))

else:
  iterator status*(repository: GitRepository; show: GitStatusShow;
                   flags = defaultStatusFlags): GitResult[GitStatus] =
    raise newException(ValueError, "you need a newer libgit2 to do that")

proc checkoutTree*(repo: GitRepository; thing: GitThing;
                   strategy = defaultCheckoutStrategy): GitResultCode =
  ## checkout a repository using a thing
  withGit:
    var
      options = cast[ptr git_checkout_options](sizeof(git_checkout_options).alloc)
      commit: ptr git_commit
      target: ptr git_annotated_commit
    defer:
      dealloc options

    block:
      # start with converting the thing to an annotated commit
      result = git_annotated_commit_lookup(addr target, repo, thing.oid).grc
      if result != grcOk:
        break
      defer:
        target.free

      # use the oid of this target to look up the commit
      let oid = git_annotated_commit_id(target)
      result = git_commit_lookup(addr commit, repo, oid).grc
      if result != grcOk:
        break
      defer:
        commit.free

      # setup our checkout options
      result = git_checkout_options_init(options,
                                         GIT_CHECKOUT_OPTIONS_VERSION).grc
      if result != grcOk:
        break

      # reset the strategy per flags
      options.checkout_strategy = setFlags(strategy)

      # checkout the tree using the commit we fetched
      result = git_checkout_tree(repo, cast[GitObject](commit), options).grc
      if result != grcOk:
        break

      # get the commit ref name
      let name = git_annotated_commit_ref(target)
      if name.isNil:
        result = git_repository_set_head_detached_from_annotated(repo, target).grc
      else:
        result = git_repository_set_head(repo, name).grc

proc checkoutTree*(repo: GitRepository; reference: string;
                   strategy = defaultCheckoutStrategy): GitResultCode =
  ## checkout a repository using a reference string
  withGit:
    block:
      thing := repo.lookupThing(reference):
        setResultAsError(result, code)
        break
      result = repo.checkoutTree(thing, strategy = strategy)

proc checkoutHead*(repo: GitRepository;
                   strategy = defaultCheckoutStrategy): GitResultCode =
  ## checkout a repository's head
  withGit:
    var
      options = cast[ptr git_checkout_options](sizeof(git_checkout_options).alloc)
    defer:
      dealloc options

    # setup our checkout options
    withResultOf git_checkout_options_init(options,
                                           GIT_CHECKOUT_OPTIONS_VERSION):
      # reset the strategy per flags
      options.checkout_strategy = setFlags(strategy)

      # checkout the head
      result = git_checkout_head(repo, options).grc

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
      assert refer != nil
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
    withResultOf git_tree_entry_bypath(addr leaf, cast[GitTree](thing.o), path):
      defer:
        leaf.free
      # if it's okay, we have to make a copy of it that the user can free,
      # because when our thing is freed, it will invalidate the leaf var.
      var
        entry: GitTreeEntry
      withResultOf git_tree_entry_dup(addr entry, leaf):
        assert entry != nil
        result.ok entry

proc treeEntryToThing*(repo: GitRepository;
                       entry: GitTreeEntry): GitResult[GitThing] =
  ## convert a tree entry into a thing
  withGit:
    var
      obj: GitObject
    withResultOf git_tree_entry_to_object(addr obj, repo, entry):
      assert obj != nil
      result.ok newThing(obj)

proc treeWalk*(tree: GitTree; mode: GitTreeWalkMode; callback: git_treewalk_cb;
               payload: pointer): GitResultCode =
  ## walk a tree and run a callback on every entry
  withGit:
    result = git_tree_walk(tree, cast[git_treewalk_mode](mode.ord.cint),
                           callback, payload).grc

proc treeWalk*(tree: GitTree; mode: GitTreeWalkMode): GitResult[GitTreeEntries] =
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
        assert dupe != nil
        cast[var GitTreeEntries](payload).add dupe

    withResultOf tree.treeWalk(mode, cast[git_treewalk_cb](walk),
                               payload = addr entries):
      result.ok entries

proc treeWalk*(tree: GitThing; mode = gtwPre): GitResult[GitTreeEntries] =
  ## the laziest way to walk a tree, ever
  result = treeWalk(cast[GitTree](tree.o), mode)

proc newRevWalk*(repo: GitRepository): GitResult[GitRevWalker] =
  ## instantiate a new walker
  withGit:
    var
      walker: GitRevWalker
    withResultOf git_revwalk_new(addr walker, repo):
      assert walker != nil
      result.ok walker

proc next*(walker: GitRevWalker): GitResult[GitOid] =
  ## try to get the next oid that we should walk to
  withGit:
    block:
      var
        oid: GitOid = cast[GitOid](sizeof(git_oid).alloc)
      withResultOf git_revwalk_next(oid, walker):
        assert oid != nil
        result.ok oid
        break
      # free the oid if we couldn't use it
      free oid

proc push*(walker: GitRevWalker; oid: GitOid): GitResultCode =
  ## add a starting oid for the walker to begin at
  withGit:
    block:
      pushee := copy(oid):
        setResultAsError(result, code)
        break
      result = git_revwalk_push(walker, pushee).grc

proc lookupCommit*(repo: GitRepository; oid: GitOid): GitResult[GitThing] =
  ## try to look a commit up in the repository with the given name
  withGit:
    var
      commit: GitCommit
    withResultOf git_commit_lookup(addr commit, repo, oid):
      assert commit != nil
      result.ok newThing(commit)

iterator revWalk*(repo: GitRepository; walker: GitRevWalker): GitResult[GitThing] =
  ## sic the walker on a repo starting with the given oid
  withGit:
    block:
      var
        future = walker.next
        oid: GitOid

      # if oid won't be populated, we'll break here
      # so we don't end up trying to free it below
      if future.isErr:
        if future.error != grcNotFound:
          yield err[GitThing](future.error)
        break

      try:
        while future.isOk:
          # the future holds the next step in the walk
          oid = future.get

          # lookup the next commit using the current oid
          commit := repo.lookupCommit(oid):
            if code != grcNotFound:
              # undefined error; emit it as such
              yield err[GitThing](code)
            # and then break iteration
            break

          # a successful lookup; yield a new thing using the commit
          block duping:
            # copy the commit so a consumer can do their own mm on it
            var
              dupe = copy(commit)
            if dupe.isErr:
              yield err[GitThing](dupe.error)
              break duping
            else:
              yield Result[GitThing, GitResultCode].ok(dupe.get)

          # fetch the next step in the walk
          future = walker.next
          if future.isErr:
            # if we didn't reach the end of iteration,
            if future.error notin {grcIterOver, grcNotFound}:
              # emit the error
              yield err[GitThing](future.error)

      finally:
        # finally free oid
        free oid

proc newPathSpec*(spec: openArray[string]): GitResult[GitPathSpec] =
  ## instantiate a new path spec from a strarray
  withGit:
    var
      ps: GitPathSpec
      list: git_strarray
    list.count = len(spec).cuint
    list.strings = cast[ptr cstring](allocCStringArray(spec))
    withResultOf git_pathspec_new(addr ps, addr list):
      assert ps != nil
      result.ok ps
    deallocCStringArray(cast[cstringArray](list.strings))

proc matchWithParent(commit: GitCommit; nth: cuint;
                     options: ptr git_diff_options): GitResultCode =
  ## grcOkay if the commit's tree intersects with the nth parent's tree;
  ## else grcNotFound if there was no intersection
  ##
  ## (this is adapted from a helper in libgit2's log.c example)
  ## https://github.com/libgit2/libgit2/blob/master/examples/log.c
  assert commit != nil
  assert options != nil
  block:
    var
      repo = git_commit_owner(commit)
      parent: ptr git_commit
      pt, ct: GitTree
      diff: GitDiff

    assert repo != nil

    # get the nth parent
    result = git_commit_parent(addr parent, commit, nth).grc
    gitTrap parent, result:
      break

    # grab the parent's tree
    result = git_commit_tree(addr pt, parent).grc
    gitTrap pt, result:
      break

    # grab the commit's tree
    result = git_commit_tree(addr ct, commit).grc
    gitTrap ct, result:
      break

    # take a diff the the two trees
    result = git_diff_tree_to_tree(addr diff, repo, pt, ct, options).grc
    gitTrap diff, result:
      break

    if git_diff_num_deltas(diff).uint == 0'u:
      result = grcNotFound

proc allParentsMatch(commit: GitCommit; options: ptr git_diff_options;
                     parents: cuint): GitResult[bool] =
  assert commit != nil
  assert options != nil
  # count matching parents
  block complete:
    for nth in 0 ..< parents:
      let
        code = matchWithParent(commit, nth.cuint, options)
      case code:
      of grcOk:
        # this feels like a match; keep going
        continue
      of grcNotFound:
        # this is fine, but it's not a match
        result.ok false
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
    # remember to free the tree later
    defer:
      free tree

    # these don't seem worth storing...
    #var matches: ptr git_pathspec_match_list
    let
      gps: uint32 = {gpsNoMatchError}.setFlags
      # match the pathspec against the tree
      code = git_pathspec_match_tree(nil, tree, gps, ps).grc
    case code:
    of grcOk:
      # this feels like a match
      result.ok true
    of grcNotFound:
      # this is fine, but it's not a match
      result.ok false
    else:
      # this is probably not that fine; error on it
      result.err code

proc parentsMatch(commit: GitCommit; options: ptr git_diff_options;
                  ps: GitPathSpec): GitResult[bool] =
  assert commit != nil
  assert options != nil
  assert ps != nil
  let
    parents: cuint = git_commit_parentcount(commit)
  if parents == 0.cuint:
    result = commit.zeroParentsMatch(ps)
  else:
    result = commit.allParentsMatch(options, parents)

iterator commitsForSpec*(repo: GitRepository;
                         spec: openArray[string]): GitResult[GitThing] =
  ## yield each commit that matches the provided pathspec
  assert repo != nil
  withGit:
    var
      options = cast[ptr git_diff_options](sizeof(git_diff_options).alloc)
    defer:
      dealloc options

    block steve:
      let
        code = git_diff_options_init(options, GIT_DIFF_OPTIONS_VERSION).grc
      if code != grcOk:
        yield err[GitThing](code)
        break steve

      options.pathspec.count = len(spec).cuint
      options.pathspec.strings = cast[ptr cstring](allocCStringArray(spec))
      # we'll free the strings array later
      defer:
        deallocCStringArray(cast[cstringArray](options.pathspec.strings))

      # setup a pathspec for matching against trees, and free it later
      ps := newPathSpec(spec):
        yield err[GitThing](code)
        break steve

      # we'll need a walker, and we'll want it freed
      walker := repo.newRevWalk:
        yield err[GitThing](code)
        break steve

      # find the head
      head := repo.getHeadOid:
        # no head, no problem
        break steve

      # start at the head
      gitTrap walker.push(head):
        break steve

      # iterate over ALL the commits
      # pass a copy of the head oid so revwalk can free it
      for rev in repo.revWalk(walker):
        # if there's an error, yield it
        if rev.isErr:
          #yield ok[GitThing](rev.get)
          yield Result[GitThing, GitResultCode].ok rev.get
          break steve
        else:
          let
            matched = rev.get.commit.parentsMatch(options, ps)
          if matched.isOk and matched.get:
            # all the parents matched, so yield this revision
            #yield ok[GitThing](rev.get)
            yield Result[GitThing, GitResultCode].ok rev.get
          else:
            # we're not going to emit this revision, so free it
            {.warning: "need var iteration".}
            #free rev.get
            if matched.isErr:
              # the matching process produced an error
              #yield err[GitThing](matched.error)
              yield Result[GitThing, GitResultCode].err matched.error
              break steve

proc tagCreateLightweight*(repo: GitRepository; target: GitThing;
                           name: string; force = false): GitResult[GitOid] =
  ## create a new lightweight tag in the repository
  assert repo != nil
  assert target != nil and target.o != nil
  withGit:
    block:
      let
        forced: cint = if force: 1 else: 0
      var
        oid: GitOid = cast[GitOid](sizeof(git_oid).alloc)
      withResultOf git_tag_create_lightweight(oid, repo, name, target.o, forced):
        assert oid != nil
        result.ok oid
        break
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
      assert upstream != nil
      result.ok upstream

proc setBranchUpstream*(branch: GitReference; name: string): GitResultCode =
  ## set the upstream for the branch to the given branch name
  assert branch != nil
  withGit:
    result = git_branch_set_upstream(branch, name).grc

proc branchRemoteName*(repo: GitRepository; branch: string): GitResult[GitBuf] =
  ## try to fetch a single remote for a remote tracking branch
  assert repo != nil
  withGit:
    var
      buff: git_buf
    # "1024 bytes oughta be enough for anybody"
    withResultOf git_buf_grow(addr buff, 1024.cuint):
      block:
        withResultOf git_branch_remote_name(addr buff, repo, branch):
          result.ok addr buff
          break
        # free the buffer if the call failed
        git_buf_dispose(addr buff)

iterator branches*(repo: GitRepository;
                   flags = {gbtLocal, gbtRemote}): GitResult[GitReference] =
  ## this time, you're just gonna have to guess at what this proc might do...
  ## (also, you're just gonna have to free your references...)
  assert repo != nil
  if gbtAll in flags or flags.len == 0:
    raise newException(Defect, "now see here, chuckles")

  withGit:
    var
      gbt = block:
        # i know this is cookin' your noodle, but
        if gbtLocal notin flags:
          gbtRemote
        elif gbtRemote notin flags:
          gbtLocal
        else:
          gbtAll
      # 'cause we're gonna need to take the addr of this value
      list = cast[git_branch_t](gbt.ord)

    # follow close 'cause it's about to get weird
    block iteration:
      var
        iter: ptr git_branch_iterator
        # create an iterator
        code = git_branch_iterator_new(addr iter, repo, list).grc
      # if we couldn't create the iterator,
      if code != grcOk:
        # then emit the error and bail
        #yield err[GitReference](code)
        yield Result[GitReference, GitResultCode].err code
        break iteration
      defer:
        iter.free

      # iterate
      while true:
        var
          branch: GitReference = nil
        # depending on whether we were able to advance,
        code = git_branch_next(addr branch, addr list, iter).grc
        case code:
        of grcOk:
          assert branch != nil
          # issue a branch result
          #yield ok(branch)
          yield Result[GitReference, GitResultCode].ok branch
        of grcIterOver:
          assert branch == nil
          # or end iteration normally
          break iteration
        else:
          assert branch == nil
          # or end iteration with an error emission
          #yield err[GitReference](code)
          yield Result[GitReference, GitResultCode].err code
          break iteration
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
      assert signature != nil
      result.ok signature

proc defaultSignature*(repo: GitRepository): GitResult[GitSignature] =
  ## create a new signature using git configuration; must be freed
  withGit:
    var
      signature: GitSignature
    withResultOf git_signature_default(addr signature, repo):
      assert signature != nil
      result.ok signature

proc defaultSignature*(repo: GitRepository; time: Time): GitResult[GitSignature] =
  ## create a new signature using git configuration; must be freed
  assert repo != nil
  result = repo.defaultSignature
  if result.isOk:
    defer:
      free result.get
    var
      sig = result.get
    assert sig != nil
    result = newSignature($sig.name, $sig.email, time)

proc tagCreate*(repo: GitRepository; target: GitThing; name: string;
                tagger: GitSignature;
                message = ""; force = false): GitResult[GitOid] =
  ## create a new tag in the repository with signature, message
  assert repo != nil
  assert target != nil and target.o != nil
  assert tagger != nil
  withGit:
    block:
      let
        forced: cint = if force: 1 else: 0
      var
        oid: GitOid = cast[GitOid](sizeof(git_oid).alloc)
      withResultOf git_tag_create(oid, repo, name, target.o,
                                  tagger, message, forced):
        assert git_oid_is_zero(oid) == 0
        result.ok oid
        break
      # free the oid if we didn't end up using it
      free oid

proc tagCreate*(repo: GitRepository; target: GitThing; name: string;
                message = ""; force = false): GitResult[GitOid] =
  ## lightweight routine to create a heavyweight signed and dated tag
  assert repo != nil
  assert target != nil and target.o != nil
  withGit:
    let
      tagger = target.committer  # the committer, as opposed to the author
    result = repo.tagCreate(target, name, tagger,
                            message = message, force = force)

proc tagCreate*(target: GitThing; name: string;
                message = ""; force = false): GitResult[GitOid] =
  ## lightweight routine to create a heavyweight signed and dated tag
  assert target != nil and target.o != nil
  withGit:
    let
      repo = target.owner        # ie. the repository that owns the target
      tagger = target.committer  # the committer, as opposed to the author
    result = repo.tagCreate(target, name, tagger,
                            message = message, force = force)

proc tagDelete*(repo: GitRepository; name: string): GitResultCode =
  ## remove a tag
  assert repo != nil
  withGit:
    result = git_tag_delete(repo, name).grc
