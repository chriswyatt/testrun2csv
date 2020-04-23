import algorithm
import hashes
import seqUtils
import streams
import strformat
import tables
import xmlparser
import xmltree

import argparse

type
    Status = enum
        error, failed, ignored, passed

const statusSeq = @[error, failed, ignored, passed]
const statusStrSeq = @["error", "failed", "ignored", "passed"]
const statusTableSize = statusSeq.len.rightSize

const ordPeriod = ord('.')
const ordZero = ord('0')
const ordNine = ord('9')
const ordAUpper = ord('A')
const ordZUpper = ord('Z')
const ordUnderscore = ord('_')
const ordALower = ord('a')
const ordZLower = ord('z')

const csvHeader = @["name", "status"]
const csvHeaderStr = join(csvHeader, ",")

type
    CsvRow = array[csvHeader.len, string]

type
    Suite = object
        name*: string
        status*: Status
        locationUrl*: string

type
    Test = object
        name*: string
        status*: Status
        locationUrl*: string
        suites*: seq[Suite]

proc hash(x: Suite): Hash =
    var h: Hash = 0

    h = h !& x.name.hash
    h = h !& x.locationUrl.hash

    result = !$h

proc hash(x: Test): Hash =
    var h: Hash = 0

    for suite in x.suites:
        h = h !& suite.hash

    h = h !& x.name.hash
    h = h !& x.locationUrl.hash

    result = !$h

proc getRoot(filePath : string) : XmlNode =
    let stream = newFileStream(filePath, fmRead)
    result = parseXml(stream)
    stream.close()

proc getStatus(statusStr : string) : Status =
    result = statusSeq[find(statusStrSeq, statusStr)]

proc parseTest(node : XmlNode) : (string, Status, string) =
    let name = node.attr("name")

    let statusStr = node.attr("status")
    let status = getStatus(statusStr)

    let locationUrl = node.attr("locationUrl")

    result = (name, status, locationUrl)

proc parseSuite(node : XmlNode, parents = newSeq[Suite]()) : seq[Test] =
    let suiteName = node.attr("name")

    let suiteStatusStr = node.attr("status")
    let suiteStatus = getStatus(suiteStatusStr)

    let suiteLocationUrl = node.attr("locationUrl")

    let suite = Suite(
        name: suiteName,
        status: suiteStatus,
        locationUrl: suiteLocationUrl,
    )

    result = newSeq[Test]()

    for child in node:
        if child.tag == "test":
            let (testName, testStatus, testLocationUrl) = parseTest(child)
            result.add(Test(
                name: testName,
                status: testStatus,
                locationUrl: testLocationUrl,
                suites: parents & @[suite],
            ))
        elif child.tag == "suite":
            for test in parseSuite(child, parents=parents & @[suite]):
                result.add(test)

proc parseRoot(root : XmlNode) : (int, CountTableRef[Status], seq[Test]) =
    var testSeq = newSeq[Test]()

    var numTests: int
    let statusCounts = newCountTable[Status](initialSize = statusTableSize)

    for child in root:
        if child.tag == "suite":
            for test in parseSuite(child):
                testSeq.add(test)
        elif child.tag == "count":
            let countName = child.attr("name")
            let countValueStr = child.attr("value")
            if countName == "total":
                numTests = parseInt(countValueStr)
            else:
                let status = getStatus(countName)

                if statusCounts.hasKey(status):
                    raise newException(ValueError, "Duplicate 'count' elements")

                statusCounts[status] = parseInt(countValueStr)

    return (numTests, statusCounts, testSeq)

proc isNameValid(name : string) : bool =
    for chk in name:
        let ordChk = ord(chk)

        if not (
                (ordChk >= ordALower and ordChk <= ordZLower) or
                (ordChk >= ordZero and ordChk <= ordNine) or
                (ordChk >= ordAUpper and ordChk <= ordZUpper) or
                ordChk == ordUnderscore or
                ordChk == ordPeriod):

            return false
    
    return true

proc validate(expectedNumTests: int, expectedStatusCounts : CountTableRef[Status], testSeq : seq[Test]) =
    let actualStatusCounts = newCountTable[Status](initialSize = statusTableSize)

    for test in testSeq:
        actualStatusCounts.inc(test.status)

    if actualStatusCounts != expectedStatusCounts:
        echo $actualStatusCounts
        echo $expectedStatusCounts
        raise newException(ValueError, "Unexpected status counts")

    var actualNumTests: int
    for count in values(actualStatusCounts):
        actualNumTests += count

    if actualNumTests != expectedNumTests:
        raise newException(ValueError, "Unexpected total")

    let testHashCounts = newCountTable[Hash](initialSize = actualNumTests.rightSize)
    for test in testSeq:
        testHashCounts.inc(test.hash)

    let largestTestHashCount = testHashCounts.largest
    if largestTestHashCount[1] > 1:
        raise newException(ValueError, "Duplicate test(s)")

    for test in testSeq:
        for suite in test.suites:
            if not isNameValid(suite.name):
                raise newException(ValueError, "Suite name invalid")

        if not isNameValid(test.name):
            raise newException(ValueError, "Test name invalid")

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

proc writeCsv(testSeq : seq[Test]) =
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
        row[1] = $test.status

        echo join(row, ",")

proc parseArgs() : string =
    let p = newParser("testrun2csv"):
        help("Convert IntelliJ testrun XML file to a CSV file")
        arg(
            "in_file",
            help = "Input file",
        )

    try:
        let opts = p.parse()
        result = opts.in_file
    except UsageError:
        p.run(@["--help"])
        raise

var inFilePath: string

try:
    inFilePath = parseArgs()
except UsageError:
    quit(QuitFailure)

let root = getRoot(inFilePath)
let (numTests, statusCounts, testSeq) = parseRoot(root)
validate(numTests, statusCounts, testSeq)
writeCsv(testSeq)
