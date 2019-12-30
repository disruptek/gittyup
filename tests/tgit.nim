import unittest

import gittyup

suite "gittyup":
  test "has working status":
    check hasWorkingStatus
