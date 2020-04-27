import hashes
import tables

type
    Status* = enum
        error, failed, ignored, passed

const statusSeq* = [error, failed, ignored, passed]
const statusStrSeq* = ["error", "failed", "ignored", "passed"]
const statusTableSize* = statusSeq.len.rightSize

type
    Suite* = ref object of RootObj
        name*: string
        status*: Status
        locationUrl*: string

type
    Test* = ref object of RootObj
        name*: string
        status*: Status
        locationUrl*: string
        suites*: seq[Suite]

proc hash*(x: Suite): Hash =
    var h: Hash = 0

    h = h !& x.name.hash
    h = h !& x.locationUrl.hash

    result = !$h

proc hash*(x: Test): Hash =
    var h: Hash = 0

    for suite in x.suites:
        h = h !& suite.hash

    h = h !& x.name.hash
    h = h !& x.locationUrl.hash

    result = !$h