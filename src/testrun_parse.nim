import hashes
import sequtils
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
        raise newException(ValueError, fmt"Duplicate test(s)")

proc getTestSeqByStatus(testSeq : seq[Test]) : Table[Status, seq[Test]] =
    result = toTable[Status, seq[Test]](zip(statusSeq, repeat(newSeq[Test](), statusSeq.len)))

    for test in testSeq:
        result[test.status].add(test)

proc writeOutput(testSeq : seq[Test]) =
    let testSeqByStatus = getTestSeqByStatus(testSeq)

    for ix, status in statusSeq:
        let statusStr = statusStrSeq[ix]
        echo statusStr
        echo '='.repeat(statusStr.len)

        for test in testSeqByStatus[status]:
            let suitePath = join(map(test.suites, proc (x: Suite): string = x.name), ".")
            echo fmt"{suitePath}::{test.name}"
        
        echo ""

proc parseArgs() : string =
    let p = newParser("testrun_parse"):
        help("Parse IntelliJ testrun XML files")
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
writeOutput(testSeq)
