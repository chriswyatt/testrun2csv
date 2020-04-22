import argparse
import streams
import strformat
import tables
import xmlparser
import xmltree

type
    Status = enum
        error, failed, ignored, passed

const statusSeq = @[error, failed, ignored, passed]
const statusStrSeq = @["error", "failed", "ignored", "passed"]
const statusTableSize = statusSeq.len.rightSize

type
    Test = object
        name*: string
        status*: Status
        locationUrl*: string

type
    Suite = object
        name*: string
        status*: Status
        locationUrl*: string
        tests*: seq[Test]

type
    TestRef = tuple
        suiteName: string
        suiteLocationUrl: string
        testName: string
        testLocationUrl: string

proc getRoot(filePath : string) : XmlNode =
    let stream = newFileStream(filePath, fmRead)
    result = parseXml(stream)
    stream.close()

proc getStatus(statusStr : string) : Status =
    result = statusSeq[find(statusStrSeq, statusStr)]

proc parseTest(node : XmlNode) : Test =
    let name = node.attr("name")

    let statusStr = node.attr("status")
    let status = getStatus(statusStr)

    let locationUrl = node.attr("locationUrl")

    result = Test(name: name, status: status, locationUrl: locationUrl)

proc parseSuite(node : XmlNode) : Suite =
    let name = node.attr("name")

    let statusStr = node.attr("status")
    let status = getStatus(statusStr)

    let locationUrl = node.attr("locationUrl")

    var testSeq = newSeq[Test]()

    for child in node:
        if child.tag == "test":
            testSeq.add(parseTest(child))

    result = Suite(name: name, status: status, locationUrl: locationUrl, tests: testSeq)

proc parseRoot(root : XmlNode) : (int, CountTableRef[Status], seq[Suite]) =
    var suiteSeq = newSeq[Suite]()

    var numTests : int
    let statusCounts = newCountTable[Status](initialSize = statusTableSize)

    for child in root:
        if child.tag == "suite":
            suiteSeq.add(parseSuite(child))
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

    return (numTests, statusCounts, suiteSeq)

proc validate(expectedNumTests: int, expectedStatusCounts : CountTableRef[Status], suiteSeq : seq[Suite]) =
    let actualStatusCounts = newCountTable[Status](initialSize = statusTableSize)

    for suite in suiteSeq:
        for test in suite.tests:
            actualStatusCounts.inc(test.status)

    if actualStatusCounts != expectedStatusCounts:
        raise newException(ValueError, "Unexpected status counts")

    var actualNumTests : int
    for count in values(actualStatusCounts):
        actualNumTests += count

    if actualNumTests != expectedNumTests:
        raise newException(ValueError, "Unexpected total")

    let testRefCounts = newCountTable[TestRef](initialSize = actualNumTests.rightSize)
    for suite in suiteSeq:
        for test in suite.tests:
            testRefCounts.inc((suiteName: suite.name, suiteLocationUrl: suite.locationUrl, testName: test.name, testLocationUrl: test.locationUrl))

    let largestTestRefCount = testRefCounts.largest
    if largestTestRefCount[1] > 1:
        raise newException(ValueError, fmt"Duplicate test: {largestTestRefCount[0]}")

proc parse_args() : string =
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

var inFilePath : string

try:
    inFilePath = parse_args()
except UsageError:
    quit(QuitFailure)

let root = getRoot(inFilePath)
let (numTests, statusCounts, suiteSeq) = parseRoot(root)
validate(numTests, statusCounts, suiteSeq)
