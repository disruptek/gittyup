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
  git2SetVer {.strdefine, used.} = "master"

when git2SetVer == "master":
  const
    hasWorkingStatus* = true
elif git2SetVer == "0.28.3" or git2SetVer == "0.28.4":
  const
    hasWorkingStatus* = false
elif git2SetVer == "v0.28.3" or git2SetVer == "v0.28.4":
  const
    hasWorkingStatus* = false
else:
  {.fatal: "libgit2 version `" & git2SetVer & "` unsupported".}

import nimgit2
import result
export result

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
                git_branch_iterator

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
    goAny         = (2 + GIT_OBJECT_ANY, "object")
    goBad         = (2 + GIT_OBJECT_INVALID, "invalid")
    goCommit      = (2 + GIT_OBJECT_COMMIT, "commit")
    goTree        = (2 + GIT_OBJECT_TREE, "tree")
    goBlob        = (2 + GIT_OBJECT_BLOB, "blob")
    goTag         = (2 + GIT_OBJECT_TAG, "tag")
    # this space intentionally left blank
    goOfsDelta    = (2 + GIT_OBJECT_OFS_DELTA, "ofs")
    goRefDelta    = (2 + GIT_OBJECT_REF_DELTA, "ref")

  GitThing* = ref object
    o*: GitObject
    case kind*: GitObjectKind:
    of goTag:
      discard
    of goRefDelta:
      discard
    of goTree:
      discard
    else:
      discard

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

  GitClone* = object
    url*: cstring
    directory*: cstring
    repo*: GitRepository
    options*: ptr git_clone_options

  GitOpen* = object
    path*: cstring
    repo*: GitRepository

  GitTagTable* = OrderedTableRef[string, GitThing]
  GitResult*[T] = Result[T, GitResultCode]

template grc(code: cint): GitResultCode = cast[GitResultCode](code.ord)
template grc(code: GitResultCode): GitResultCode = code
template gec(code: cint): GitErrorClass = cast[GitErrorClass](code.ord)

proc hash*(gcs: GitCheckoutStrategy): Hash = gcs.ord.hash

const
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

template gitFail*(allocd: typed; code: GitResultCode; body: untyped) =
  ## a version of gitTrap that expects failure; no error messages!
  defer:
    if code == grcOk:
      free(allocd)
  if code != grcOk:
    body

template gitFail*(code: GitResultCode; body: untyped) =
  ## a version of gitTrap that expects failure; no error messages!
  if code != grcOk:
    body

template gitTrap*(allocd: typed; code: GitResultCode; body: untyped) =
  defer:
    if code == grcOk:
      free(allocd)
  if code != grcOk:
    dumpError()
    body

template gitTrap*(code: GitResultCode; body: untyped) =
  if code != grcOk:
    dumpError()
    body

template ok*(self: var GitResult; x: auto) = result.ok(self.Result, x)
template err*(self: var GitResult; x: auto) = result.err(self.Result, x)
template ok*[T](v: T): auto = typeof(result).ok(v)
template err*[T](v: T): auto = typeof(result).err(v)
template newResult[T](code: GitResultCode): GitResult[T] =
  (var result = GitResult[T](); result.err code; result)
template newResult[T](value: T): GitResult[T] =
  (var result = GitResult[T](); result.ok value; result)

#template `:=`(v: untyped{nkIdent}; vv: Result): bool =
#  (let vr = vv; template v: auto = unsafeGet(vr); vr.isOk)

template `:=`*[T](v: untyped{nkIdent}; vv: Result[T, GitResultCode];
                  body: untyped): untyped =
  let vr = vv
  template v: auto {.used.} = unsafeGet(vr)
  defer:
    if isOk(vr):
      when defined(debugGit):
        debug "freeing ", $v
      free(unsafeGet(vr))
  if not isOk(vr):
    var code {.used, inject.} = vr.error
    when defined(debugGit):
      debug "failure ", $v, ": ", $code
    body

proc normalizeUrl(uri: Uri): Uri =
  result = uri
  if result.scheme == "" and result.path.startsWith("git@github.com:"):
    result.path = result.path["git@github.com:".len .. ^1]
    result.username = "git"
    result.hostname = "github.com"
    result.scheme = "ssh"

proc init*(): bool =
  let count = git_libgit2_init()
  result = count > 0
  when defined(debugGit):
    debug "open gits:", count

proc shutdown*(): bool =
  let count = git_libgit2_shutdown()
  result = count >= 0
  when defined(debugGit):
    debug "open gits:", count

template withGit(body: untyped) =
  once:
    if not init():
      raise newException(OSError, "unable to init git")
  when defined(gitShutsDown):
    defer:
      if not shutdown():
        raise newException(OSError, "unable to shut git")
  body

template setResultAsError(code: typed) =
  when declaredInScope(result):
    when result is GitResultCode:
      result = grc(code)
    elif result of GitResult:
      result.err grc(code)

template withGitRepoAt(path: string; body: untyped) =
  ## run the body, opening `repo` at the given `path`.
  ## sets the proper return value in the event of error.
  ## note that this introduces scope.
  withGit:
    block:
      repository := openRepository(path):
        setResultAsError(code)
        break
      var repo {.inject.} = repository
      body

template withResultOf(gitsaid: cint; body: untyped) =
  ## when git said there was an error, set the result code;
  ## else, run the body
  if grc(gitsaid) == grcOk:
    body
  else:
    setResultAsError(gitsaid)

template demandGitRepoAt(path: string; body: untyped) =
  withGit:
    block:
      repository := openRepository(path):
        # quirky-esque exception purposes
        setResultAsError(code)
        let emsg = &"error opening {path}: {code}"
        raise newException(IOError, emsg)
      var repo {.inject.} = repository
      body

proc free*[T: GitHeapGits](point: ptr T) =
  withGit:
    if point != nil:
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
      else:
        {.error: "missing a free definition for " & $typeof(T).}

proc free*[T: NimHeapGits](point: ptr T) =
  if point != nil:
    dealloc(point)

proc free*(clone: GitClone) =
  withGit:
    free(clone.repo)
    free(clone.options)

proc free*(opened: GitOpen) =
  withGit:
    free(opened.repo)

proc free*(thing: GitThing) =
  withGit:
    free(thing.o)

proc free*(entries: GitTreeEntries) =
  withGit:
    for entry in entries.items:
      free(entry)

proc short*(oid: GitOid; size: int): string =
  var
    output: cstring
  withGit:
    output = cast[cstring](alloc(size + 1))
    output[size] = '\0'
    git_oid_nfmt(output, size.uint, oid)
    result = $output
    dealloc(output)

proc url*(remote: GitRemote): Uri =
  ## retrieve the url of a remote
  withGit:
    result = parseUri($git_remote_url(remote)).normalizeUrl

func name*(entry: GitTreeEntry): string =
  result = $git_tree_entry_name(entry)

func name*(remote: GitRemote): string =
  result = $git_remote_name(remote)

func `$`*(remote: GitRemote): string =
  result = remote.name

func `$`*(repo: GitRepository): string =
  result = $git_repository_path(repo)

func `$`*(buffer: ptr git_buf): string =
  result = $cast[cstring](buffer)

func `$`*(annotated: ptr git_annotated_commit): string =
  result = $git_annotated_commit_ref(annotated)

func `$`*(oid: GitOid): string =
  result = $git_oid_tostr_s(oid)

func `$`*(tag: GitTag): string =
  if tag != nil:
    let
      name = git_tag_name(tag)
    if name != nil:
      result = $name

proc oid*(entry: GitTreeEntry): GitOid =
  result = git_tree_entry_id(entry)

proc oid*(got: GitReference): GitOid =
  result = git_reference_target(got)

proc oid*(obj: GitObject): GitOid =
  result = git_object_id(obj)

proc oid*(thing: GitThing): GitOid =
  result = thing.o.oid

proc oid*(tag: GitTag): GitOid =
  result = git_tag_id(tag)

proc branchName*(got: GitReference): string =
  ## fetch a branch name assuming the reference is a branch
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

func isTag*(got: GitReference): bool =
  result = git_reference_is_tag(got) == 1

proc isBranch*(got: GitReference): bool =
  withGit:
    result = git_reference_is_branch(got) == 1

func name*(got: GitReference): string =
  result = $git_reference_name(got)

proc owner*(thing: GitThing): GitRepository =
  ## retrieve the repository that owns this thing
  result = git_object_owner(thing.o)

proc owner*(commit: GitCommit): GitRepository =
  ## retrieve the repository that owns this commit
  result = git_commit_owner(commit)

proc owner*(reference: GitReference): GitRepository =
  ## retrieve the repository that owns this reference
  result = git_reference_owner(reference)

proc flags*(status: GitStatus): set[GitStatusFlag] =
  ## produce the set of flags indicating the status of the file
  for flag in GitStatusFlag.low .. GitStatusFlag.high:
    if flag.ord.uint == bitand(status.status.uint, flag.ord.uint):
      result.incl flag

proc setFlags[T](flags: seq[T] | set[T] | HashSet[T]): cuint =
  for flag in flags.items:
    result = bitor(result, flag.ord.cuint).cuint

func `$`*(reference: GitReference): string =
  if reference.isTag:
    result = reference.name
  else:
    result = $reference.oid

func `$`*(entry: GitTreeEntry): string =
  result = entry.name

func `$`*(obj: GitObject): string =
  result = $(git_object_type(obj).git_object_type2string)
  result &= "-" & $obj.git_object_id

func `$`*(thing: GitThing): string =
  result = $thing.o

func `$`*(status: GitStatus): string =
  for flag in status.flags.items:
    if result != "":
      result &= ","
    result &= $flag

proc message*(commit: GitCommit): string =
  withGit:
    result = $git_commit_message(commit)

proc message*(tag: GitTag): string =
  withGit:
    result = $git_tag_message(tag)

proc message*(thing: GitThing): string =
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
    result = $git_commit_summary(commit)

proc summary*(thing: GitThing): string =
  case thing.kind:
  of goTag:
    result = cast[GitTag](thing.o).message
  of goCommit:
    result = cast[GitCommit](thing.o).summary
  else:
    raise newException(ValueError, "dunno how to get a summary: " & $thing)
  result = result.strip

func `$`*(commit: GitCommit): string =
  result = $cast[GitObject](commit)

proc free*(table: var GitTagTable) =
  ## free a tag table
  withGit:
    for tag, obj in table.pairs:
      when tag is GitTag:
        tag.free
        obj.free
      elif tag is string:
        obj.free
      elif tag is GitThing:
        let
          same = tag == obj
        tag.free
        # make sure we don't free the same object twice
        if not same:
          obj.free
    table.clear

proc hash*(oid: GitOid): Hash =
  var h: Hash = 0
  h = h !& hash($oid)
  result = !$h

proc hash*(tag: GitTag): Hash =
  var h: Hash = 0
  h = h !& hash($tag)
  result = !$h

proc hash*(thing: GitThing): Hash =
  var h: Hash = 0
  h = h !& hash($thing.oid)
  result = !$h

proc kind(obj: GitObject): GitObjectKind =
  withGit:
    let
      typeName = $(git_object_type(obj).git_object_type2string)
    result = parseEnum[GitObjectKind](typeName)

proc newThing(obj: GitObject): GitThing =
  try:
    result = GitThing(kind: obj.kind, o: obj)
  except:
    result = GitThing(kind: goAny, o: obj)

proc toThing*(commit: GitCommit): GitThing =
  result = newThing(cast[GitObject](commit))

proc clone*(uri: Uri; path: string; branch = ""): GitResult[GitRepository] =
  ## clone a repository
  withGit:
    var
      options = cast[ptr git_clone_options](sizeof(git_clone_options).alloc)
    defer:
      options.dealloc
    withResultOf git_clone_options_init(options, GIT_CLONE_OPTIONS_VERSION):
      if branch != "":
        options.checkout_branch = branch
      var
        repo: GitRepository
      withResultOf git_clone(addr repo, $uri, path, options):
        result.ok repo

proc setHeadDetached*(repo: GitRepository; oid: GitOid): GitResultCode =
  ## detach the HEAD and point it at the given OID
  withGit:
    result = git_repository_set_head_detached(repo, oid).grc

proc setHeadDetached*(repo: GitRepository; reference: string): GitResultCode =
  ## point the repo's head at the given reference
  var
    oid: ptr git_oid = cast[ptr git_oid](sizeof(git_oid).alloc)
  defer:
    oid.free
  withGit:
    result = git_oid_fromstr(oid, reference).grc
    if result == grcOk:
      result = repo.setHeadDetached(oid)

proc openRepository*(path: string): GitResult[GitRepository] =
  ## open a repository by path; the repository must be freed
  withGit:
    var
      repo: GitRepository
    withResultOf git_repository_open(addr repo, path):
      result.ok repo

proc openRepository*(got: var GitOpen; path: string): GitResultCode
  {.deprecated.} =
  ## open a repository by path
  got.path = path
  withGit:
    result = git_repository_open(addr got.repo, got.path).grc

proc repositoryHead*(repo: GitRepository): GitResult[GitReference] =
  ## fetch the reference for the repository's head; the reference must be freed
  withGit:
    var
      head: GitReference
    withResultOf git_repository_head(addr head, repo):
      result.ok head

proc repositoryHead*(head: var GitReference; repo: GitRepository): GitResultCode
  {.deprecated.} =
  ## fetch the reference for the repository's head
  withGit:
    result = git_repository_head(addr head, repo).grc

proc repositoryHead*(head: var GitReference; path: string): GitResultCode
  {.deprecated.} =
  ## fetch the reference for the head of the repository at the given path
  withGitRepoAt(path):
    result = repositoryHead(head, repo)

proc headReference*(repo: GitRepository): GitResult[GitReference] =
  ## alias for repositoryHead
  result = repositoryHead(repo)

proc remoteLookup*(repo: GitRepository; name: string): GitResult[GitRemote] =
  ## get the remote by name; the remote must be freed
  withGit:
    var
      remote: GitRemote
    withResultOf git_remote_lookup(addr remote, repo, name):
      result.ok remote

proc remoteLookup*(remote: var GitRemote; repo: GitRepository;
                   name: string): GitResultCode {.deprecated.} =
  ## get the remote by name
  withGit:
    result = git_remote_lookup(addr remote, repo, name).grc

proc remoteLookup*(remote: var GitRemote; path: string;
                   name: string): GitResultCode {.deprecated.} =
  ## get the remote by name using a repository path
  withGitRepoAt(path):
    result = remoteLookup(remote, repo, name)

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
        result.ok cstringArrayToSeq(cast[cstringArray](list.strings),
                                    list.count)

proc remoteRename*(path: string; prior: string; next: string): GitResultCode
  {.deprecated.} =
  ## rename a remote in the repository at the given path
  withGitRepoAt(path):
    let
      rename = repo.remoteRename(prior, next)
    if rename.isOk:
      result = grcOk
    else:
      result = rename.error

proc remoteDelete*(repo: GitRepository; name: string): GitResultCode =
  ## delete a remote from the repository
  withGit:
    result = git_remote_delete(repo, name).grc

proc remoteDelete*(path: string; name: string): GitResultCode {.deprecated.} =
  ## delete a remote from the repository at the given path
  withGitRepoAt(path):
    result = remoteDelete(repo, name)

proc remoteCreate*(repo: GitRepository; name: string;
                   url: Uri): GitResult[GitRemote] =
  ## create a new remote in the repository
  withGit:
    var
      remote: GitRemote
    withResultOf git_remote_create(addr remote, repo, name, $url):
      result.ok remote

proc remoteCreate*(remote: var GitRemote; repo: GitRepository;
                   name: string; url: Uri): GitResultCode {.deprecated.} =
  ## create a new remote in the repository
  withGit:
    result = git_remote_create(addr remote, repo, name, $url).grc

proc remoteCreate*(remote: var GitRemote; path: string;
                   name: string; url: Uri): GitResultCode {.deprecated.} =
  ## create a new remote in the repository at the given path
  withGitRepoAt(path):
    result = remoteCreate(remote, repo, name, url)

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

proc target*(thing: GitThing; target: var GitThing): GitResultCode =
  var
    obj: GitObject
  withGit:
    result = git_tag_target(addr obj, cast[GitTag](thing.o)).grc
    if result == grcOk:
      target = newThing(obj)

proc tagList*(repo: GitRepository; tags: var seq[string]): GitResultCode =
  ## retrieve a list of tags from the repo
  var
    list: git_strarray
  withGit:
    result = git_tag_list(addr list, repo).grc
    if result == grcOk:
      defer:
        git_strarray_free(addr list)
      if list.count > 0'u:
        tags = cstringArrayToSeq(cast[cstringArray](list.strings), list.count)

proc lookupThing*(repo: GitRepository; name: string): GitResult[GitThing] =
  ## try to look some thing up in the repository with the given name
  withGit:
    var
      obj: GitObject
    let
      code = git_revparse_single(addr obj, repo, name).grc
    if code == grcOk:
      result.ok newThing(obj)
    else:
      result.err code

proc lookupThing*(thing: var GitThing; repo: GitRepository;
                  name: string): GitResultCode {.deprecated.} =
  ## try to look some thing up in the repository with the given name
  var
    obj: GitObject
  withGit:
    result = git_revparse_single(addr obj, repo, name).grc
    if result == grcOk:
      thing = newThing(obj)

proc lookupThing*(thing: var GitThing; path: string;
                  name: string): GitResultCode {.deprecated.} =
  ## try to look some thing up in the repository at the given path
  withGitRepoAt(path):
    result = lookupThing(thing, repo, name)

proc newTagTable*(size = 32): GitTagTable =
  ## instantiate a new table
  result = newOrderedTable[string, GitThing](size)

proc tagTable*(repo: GitRepository; tags: var GitTagTable): GitResultCode =
  ## compose a table of tags and their associated references
  var
    names: seq[string]

  tags = newTagTable()

  result = tagList(repo, names)
  block:
    if result != grcOk:
      break

    for name in names.items:
      var
        thing, target: GitThing
      result = lookupThing(thing, repo, name)
      if result != grcOk:
        debug &"failed lookup for `{name}`"
        continue

      if thing.kind != goTag:
        target = thing
      else:
        result = thing.target(target)
        free(thing)
        if result != grcOk:
          debug &"failed target for `{name}`"
          continue
      tags.add name, target

proc tagTable*(path: string; tags: var GitTagTable): GitResultCode
  {.deprecated.} =
  ## compose a table of tags and their associated references
  withGitRepoAt(path):
    result = repo.tagTable(tags)

proc shortestTag*(table: GitTagTable; oid: string): string =
  ## pick the shortest tag that matches the oid supplied
  for name, thing in table.pairs:
    if $thing.oid != oid:
      continue
    if result == "" or name.len < result.len:
      result = name
  if result == "":
    result = oid

proc getHeadOid*(repository: GitRepository): GitResult[GitOid] =
  ## try to retrieve the #head oid from a repository
  withGit:
    let
      head = repository.headReference
    if head.isOk:
      result.ok head.get.oid
    else:
      result.err head.error

proc getHeadOid*(path: string): GitResult[GitOid] =
  ## try to retrieve the #head oid from a repository at the given path
  demandGitRepoAt(path):
    result = repo.getHeadOid

proc repositoryState*(repository: GitRepository): GitRepoState =
  ## fetch the state of a repository
  withGit:
    result = cast[GitRepoState](git_repository_state(repository))

proc repositoryState*(path: string): GitRepoState =
  ## fetch the state of the repository at the given path
  demandGitRepoAt(path):
    result = repositoryState(repo)

when hasWorkingStatus == true:
  iterator status*(repository: GitRepository; show: GitStatusShow;
                   flags = defaultStatusFlags): GitResult[GitStatus] =
    ## iterate over files in the repo using the given search flags
    withGit:
      var
        statum: GitStatusList
        options = cast[ptr git_status_options](sizeof(git_status_options).alloc)
      defer:
        options.free

      block:
        var
          code = git_status_options_init(options, GIT_STATUS_OPTIONS_VERSION).grc
        if code != grcOk:
          # throw the error code
          yield newResult[GitStatus](code)
          break

        options.show = cast[git_status_show_t](show)
        for flag in flags.items:
          options.flags = bitand(options.flags.uint, flag.ord.uint).cuint

        code = git_status_list_new(addr statum, repository, options).grc
        if code != grcOk:
          # throw the error code
          yield newResult[GitStatus](code)
          break
        defer:
          statum.free

        let
          count = git_status_list_entrycount(statum)
        for index in 0 ..< count:
          yield newResult[GitStatus](git_status_byindex(statum, index.cuint))

else:
  iterator status*(repository: GitRepository; show: GitStatusShow;
                   flags = defaultStatusFlags): GitResult[GitStatus] =
    raise newException(ValueError, "you need a newer libgit2 to do that")

iterator status*(path: string; show = ssIndexAndWorkdir;
                 flags = defaultStatusFlags): GitResult[GitStatus] =
  ## for repository at path, yield status for each file which trips the flags
  demandGitRepoAt(path):
    for entry in status(repo, show, flags):
      yield entry

proc checkoutTree*(repo: GitRepository; thing: GitThing;
                   strategy = defaultCheckoutStrategy): GitResultCode =
  ## checkout a repository using a thing
  withGit:
    var
      options = cast[ptr git_checkout_options](sizeof(git_checkout_options).alloc)
      commit: ptr git_commit
      target: ptr git_annotated_commit
    defer:
      options.free

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
    var
      thing: GitThing
    result = lookupThing(thing, repo, reference)
    if result == grcOk:
      defer:
        thing.free
      result = checkoutTree(repo, thing, strategy = strategy)

proc checkoutTree*(path: string; reference: string;
                   strategy = defaultCheckoutStrategy): GitResultCode =
  ## checkout a repository in the given path using a reference string
  withGitRepoAt(path):
    result = checkoutTree(repo, reference, strategy = strategy)

proc checkoutHead*(repo: GitRepository;
                   strategy = defaultCheckoutStrategy): GitResultCode =
  ## checkout a repository's head
  withGit:
    var
      options = cast[ptr git_checkout_options](sizeof(git_checkout_options).alloc)
    defer:
      options.free

    block:
      # setup our checkout options
      result = git_checkout_options_init(options,
                                         GIT_CHECKOUT_OPTIONS_VERSION).grc
      if result != grcOk:
        break

      # reset the strategy per flags
      options.checkout_strategy = setFlags(strategy)

      # checkout the head
      result = git_checkout_head(repo, options).grc
      if result != grcOk:
        break

proc setHead*(repo: GitRepository; short: string): GitResultCode =
  ## set the head of a repository
  withGit:
    result = git_repository_set_head(repo, short.cstring).grc

proc setHead*(path: string; short: string): GitResultCode =
  ## set the head of a repository at the given path
  withGitRepoAt(path):
    result = repo.setHead(short)

proc referenceDWIM*(refer: var GitReference;
                    repo: GitRepository;
                    short: string): GitResultCode =
  ## turn a string into a reference
  withGit:
    result = git_reference_dwim(addr refer, repo, short).grc

proc referenceDWIM*(refer: var GitReference; path: string;
                    short: string): GitResultCode =
  ## turn a string into a reference
  withGitRepoAt(path):
    result = referenceDWIM(refer, repo, short)

proc checkoutHead*(path: string;
                   strategy = defaultCheckoutStrategy): GitResultCode =
  ## checkout a repository's head in the given path using a reference string
  withGitRepoAt(path):
    result = checkoutHead(repo, strategy = strategy)

proc lookupTreeThing*(thing: var GitThing;
                      repo: GitRepository; path = "HEAD"): GitResultCode =
    result = thing.lookupThing(repo, path & "^{tree}")

proc lookupTreeThing*(thing: var GitThing;
                      repository: string; path = "HEAD"): GitResultCode
  {.deprecated.} =
  withGitRepoAt(repository):
    result = thing.lookupThing(repo, path & "^{tree}")

proc treeEntryByPath*(entry: var GitTreeEntry; thing: GitThing;
                      path: string): GitResultCode =
  ## get a tree entry using its path and that of the repo
  withGit:
    var
      leaf: GitTreeEntry
    # get the entry by path using the thing as a tree
    result = git_tree_entry_bypath(addr leaf, cast[GitTree](thing.o), path).grc
    if result == grcOk:
      defer:
        leaf.free
      # if it's okay, we have to make a copy of it that the user can free,
      # because when our thing is freed, it will invalidate the leaf var.
      result = git_tree_entry_dup(addr entry, leaf).grc

proc treeEntryByPath*(entry: var GitTreeEntry; repo: GitRepository;
                      path: string): GitResultCode =
  ## get a tree entry using its path and that of the repo
  withGit:
    var thing: GitThing
    result = thing.lookupTreeThing(repo, path = "HEAD")
    if result != grcOk:
      warn &"unable to lookup HEAD for {path}"
    else:
      defer: thing.free
      result = treeEntryByPath(entry, thing, path)

proc treeEntryByPath*(entry: var GitTreeEntry; at: string;
                      path: string): GitResultCode =
  ## get a tree entry using its path and that of the repo
  withGitRepoAt(at):
    result = treeEntryByPath(entry, repo, path)

proc treeEntryToThing*(thing: var GitThing; repo: GitRepository;
                       entry: GitTreeEntry): GitResultCode =
  ## convert a tree entry into a thing
  withGit:
    var obj: GitObject
    result = git_tree_entry_to_object(addr obj, repo, entry).grc
    if result == grcOk:
      thing = newThing(obj)

proc treeEntryToThing*(thing: var GitThing; at: string;
                       entry: GitTreeEntry): GitResultCode =
  ## convert a tree entry into a thing using the repo at the given path
  withGitRepoAt(at):
    result = treeEntryToThing(thing, repo, entry)

proc treeWalk*(tree: GitTree; mode: GitTreeWalkMode;
               callback: git_treewalk_cb;
               payload: pointer): GitResultCode =
  ## walk a tree and run a callback on every entry
  withGit:
    result = git_tree_walk(tree,
                           cast[git_treewalk_mode](mode.ord.cint),
                           callback, payload).grc

proc treeWalk*(tree: GitTree;
               mode: GitTreeWalkMode): Option[GitTreeEntries] =
  ## try to walk a tree and return a sequence of its entries
  withGit:
    var
      entries: GitTreeEntries

  proc walk(root: cstring; entry: ptr git_tree_entry;
             payload: pointer): cint {.exportc.} =
    # a good way to get a round
    var dupe: GitTreeEntry
    if git_tree_entry_dup(addr dupe, entry).grc == grcOk:
      cast[var GitTreeEntries](payload).add dupe

  if grcOk == tree.treeWalk(mode, cast[git_treewalk_cb](walk),
                            payload = addr entries):
    result = entries.some

proc treeWalk*(tree: GitThing; mode = gtwPre): Option[GitTreeEntries] =
  ## the laziest way to walk a tree, ever
  result = treeWalk(cast[GitTree](tree.o), mode)

proc newRevWalk*(walker: var GitRevWalker; repo: GitRepository): GitResultCode =
  ## instantiate a new walker
  withGit:
    result = git_revwalk_new(addr walker, repo).grc

proc newRevWalk*(walker: var GitRevWalker; path: string): GitResultCode =
  ## instantiate a new walker from a repo at the given path
  withGitRepoAt(path):
    result = newRevWalk(walker, repo)

proc next*(oid: var git_oid; walker: GitRevWalker): GitResultCode =
  ## walk to the next node
  withGit:
    result = git_revwalk_next(addr oid, walker).grc

proc push*(walker: var GitRevWalker; oid: GitOid): GitResultCode =
  ## add a tree to be walked
  withGit:
    result = git_revwalk_push(walker, oid).grc

iterator revWalk*(repo: GitRepository; walker: GitRevWalker;
                  start: GitOid): GitCommit =
  ## sic the walker on a repo starting with the given oid
  withGit:
    var
      oid = cast[git_oid](start[])
      commit: GitCommit
    while true:
      gitTrap commit, git_commit_lookup(addr commit, repo, addr oid).grc:
        warn &"unexpected error while walking {oid}:"
        dumpError()
        break
      yield commit
      gitTrap next(oid, walker):
        break

iterator revWalk*(path: string; walker: GitRevWalker; start: GitOid): GitCommit =
  ## starting with the given oid, sic the walker on a repo at the given path
  withGitRepoAt(path):
    for commit in revWalk(repo, walker, start):
      yield commit

proc newPathSpec*(ps: var GitPathSpec; spec: openArray[string]): GitResultCode =
  ## instantiate a new path spec from a strarray
  withGit:
    var list: git_strarray
    list.count = len(spec).cuint
    list.strings = cast[ptr cstring](allocCStringArray(spec))
    result = git_pathspec_new(addr ps, addr list).grc
    deallocCStringArray(cast[cstringArray](list.strings))

proc matchWithParent(commit: ptr git_commit; nth: cuint;
                     options: ptr git_diff_options): GitResultCode =
  ## grcOkay if the commit's tree intersects with the nth parent's tree;
  ## else grcNotFound if there was no intersection
  ##
  ## (this is adapted from a helper in libgit2's log.c example)
  ## https://github.com/libgit2/libgit2/blob/master/examples/log.c
  block:
    var
      parent: ptr git_commit
      pt, ct: GitTree
      diff: GitDiff

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
    result = git_diff_tree_to_tree(addr diff,
                                   git_commit_owner(commit),
                                   pt, ct, options).grc
    gitTrap diff, result:
      break

    if git_diff_num_deltas(diff).uint == 0'u:
      result = grcNotFound

iterator commitsForSpec*(repo: GitRepository;
                         spec: openArray[string]): GitCommit =
  ## yield each commit that matches the provided pathspec
  withGit:
    var
      options = cast[ptr git_diff_options](sizeof(git_diff_options).alloc)
    defer:
      options.free

    block master:
      var
        ps: GitPathSpec
        walker: GitRevWalker
        grc: GitResultCode

      # options for matching against n parent trees
      if grcOk != git_diff_options_init(options, GIT_DIFF_OPTIONS_VERSION).grc:
        break
      options.pathspec.count = len(spec).cuint
      options.pathspec.strings = cast[ptr cstring](allocCStringArray(spec))
      defer:
        deallocCStringArray(cast[cstringArray](options.pathspec.strings))

      # setting up a similar pathspec for matching against trees
      gitTrap ps, newPathSpec(ps, spec):
        break

      # we'll need a walker
      gitTrap walker, newRevWalk(walker, repo):
        break

      # find the head
      let head = repo.getHeadOid
      if head.isErr:
        # no head, no problem
        break

      # start at the head
      gitTrap walker.push(head.get):
        break

      # iterate over ALL the commits
      for commit in repo.revWalk(walker, head.get):
        let
          parents = git_commit_parentcount(commit)
        var
          unmatched = parents
        case parents:
        of 0:
          var tree: ptr git_tree
          gitTrap tree, git_commit_tree(addr tree, commit).grc:
            break master

          # these don't seem worth storing...
          #var matches: ptr git_pathspec_match_list
          let gps: uint32 = {gpsNoMatchError}.setFlags
          gitFail git_pathspec_match_tree(nil, tree, gps, ps).grc:
            # ie. continue the revwalk
            continue
        else:
          for nth in 0 ..< parents:
            gitTrap matchWithParent(commit, nth, options):
              continue
            unmatched.dec

        # all the parents matched
        if unmatched == 0:
          yield commit

iterator commitsForSpec*(path: string; spec: openArray[string]): GitCommit =
  ## yield each commit that matches the provided pathspec
  withGitRepoAt(path):
    for commit in commitsForSpec(repo, spec):
      yield commit

proc tagCreateLightweight*(oid: var GitOid; repo: GitRepository; name: string;
                           target: GitThing; force = false): GitResultCode =
  ## create a new lightweight tag in the repository
  withGit:
    let
      forced: cint = if force: 1 else: 0
    oid = cast[ptr git_oid](sizeof(git_oid).alloc)
    result = git_tag_create_lightweight(oid,
                                        repo, name, target.o, forced).grc
    if result != grcOk:
      defer:
        oid.free

proc tagCreateLightweight*(oid: var GitOid; path: string; name: string;
                           target: GitThing; force = false): GitResultCode =
  ## create a new lightweight tag in the repository
  withGitRepoAt(path):
    result = tagCreateLightweight(oid, repo, name, target, force = force)

proc branchUpstream*(upstream: var GitReference;
                     branch: GitReference): GitResultCode =
  ## retrieve remote tracking reference for a branch reference
  withGit:
    result = git_branch_upstream(addr upstream, branch).grc

proc setBranchUpstream*(branch: GitReference; name: string): GitResultCode =
  ## set the upstream for the branch to the given branch name
  withGit:
    result = git_branch_set_upstream(branch, name).grc

proc branchRemoteName*(buffer: var GitBuf; repo: GitRepository;
                       branch: string): GitResultCode =
  ## try to fetch a single remote for a remote tracking branch
  withGit:
    var
      buff: git_buf
    # "1024 bytes oughta be enough for anybody"
    result = git_buf_grow(addr buff, 1024.cuint).grc
    if result == grcOk:
      result = git_branch_remote_name(addr buff, repo, branch).grc
      if result == grcOk:
        buffer = addr buff
      else:
        git_buf_dispose(addr buff)

proc branchRemoteName*(buffer: var GitBuf; path: string;
                       branch: string): GitResultCode =
  ## try to fetch a single remote for a remote tracking branch
  withGitRepoAt(path):
    result = branchRemoteName(buffer, repo, branch)

iterator branches*(repo: GitRepository;
                   flags = {gbtLocal, gbtRemote}): GitReference =
  ## this time, you're just gonna have to guess at what this proc might do...
  if gbtAll in flags or flags.len == 0:
    raise newException(Defect, "now see here, chuckles")

  withGit:
    var
      grc: GitResultCode
      gbt: GitBranchType = gbtAll
      iter: ptr git_branch_iterator
      branch: GitReference
      list: git_branch_t
    # i know this is cookin' your noodle, but
    if gbtLocal notin flags:
      gbt = gbtRemote
    elif gbtRemote notin flags:
      gbt = gbtLocal

    # we're gonna need to take the addr of this value
    list = cast[git_branch_t](gbt.ord)

    # follow close 'cause it's about to get weird
    block iteration:
      # create an iterator
      grc = git_branch_iterator_new(addr iter, repo, list).grc
      gitTrap iter, grc:
        dumpError()
        break iteration
      # iterate
      while true:
        grc = git_branch_next(addr branch, addr list, iter).grc
        gitFail branch, grc:
          if grc != grcIterOver:
            dumpError()
          break iteration
        yield branch
    # now, look, i tol' you it was gonna get weird; it's
    # your own fault you weren't paying attention

iterator branches*(path: string;
                   flags = {gbtLocal, gbtRemote}): GitReference =
  ## we've been here before
  withGitRepoAt(path):
    for branch in repo.branches(flags = flags):
      yield branch

proc hasThing*(tags: GitTagTable; thing: GitThing): bool =
  ## true if the thing is tagged
  for commit in tags.values:
    result = commit.oid == thing.oid
    if result:
      break
