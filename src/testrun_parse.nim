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
    Suite = object
        name*: string
        status*: Status
        locationUrl*: string

type
    Test = object
        name*: string
        status*: Status
        locationUrl*: string
        suite*: Suite

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

proc parseTest(node : XmlNode) : (string, Status, string) =
    let name = node.attr("name")

    let statusStr = node.attr("status")
    let status = getStatus(statusStr)

    let locationUrl = node.attr("locationUrl")

    result = (name, status, locationUrl)

proc parseSuite(node : XmlNode) : seq[Test] =
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
                suite: suite,
            ))

proc parseRoot(root : XmlNode) : (int, CountTableRef[Status], seq[Test]) =
    var testSeq = newSeq[Test]()

    var numTests : int
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
        raise newException(ValueError, "Unexpected status counts")

    var actualNumTests : int
    for count in values(actualStatusCounts):
        actualNumTests += count

    if actualNumTests != expectedNumTests:
        raise newException(ValueError, "Unexpected total")

    let testRefCounts = newCountTable[TestRef](initialSize = actualNumTests.rightSize)
    for test in testSeq:
        testRefCounts.inc((
            suiteName: test.suite.name,
            suiteLocationUrl: test.suite.locationUrl,
            testName: test.name,
            testLocationUrl: test.locationUrl,
        ))

    let largestTestRefCount = testRefCounts.largest
    if largestTestRefCount[1] > 1:
        raise newException(ValueError, fmt"Duplicate test: {largestTestRefCount[0]}")

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

var inFilePath : string

try:
    inFilePath = parseArgs()
except UsageError:
    quit(QuitFailure)

let root = getRoot(inFilePath)
let (numTests, statusCounts, testSeq) = parseRoot(root)
validate(numTests, statusCounts, testSeq)
