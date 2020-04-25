import algorithm
import sequtils
import streams
import strformat
import strutils

import testrun_shared

const csvHeader = ["name", "status"]
const csvHeaderStr = join(csvHeader, ",")

type
    CsvRow = array[csvHeader.len, string]

proc testCmp(x, y: Test): int =
    let minSuitesLen = min(x.suites.len, y.suites.len)

    if minSuitesLen > 0:
        for ix in 0 .. minSuitesLen - 1:
            if x.suites[ix].name < y.suites[ix].name:
                return -1
            elif x.suites[ix].name > y.suites[ix].name:
                return 1

    if x.suites.len > y.suites.len:
        return 1
    elif x.name < y.name:
        return -1
    elif x.name > y.name:
        return 1
    else:
        return 0

proc getStatusStr(status: Status): string =
    result = statusStrSeq[find(statusSeq, status)]

proc writeCsv*(testSeq: seq[Test]) =
    echo csvHeaderStr

    var row : CsvRow

    for test in sorted(testSeq, testCmp):
        let suitePath = join(map(
            test.suites,
            proc (x: Suite): string = x.name),
            ".",
        )
        let fullName = fmt"{suitePath}::{test.name}"

        row[0] = fullName
        row[1] = getStatusStr(test.status)

        echo join(row, ",")
