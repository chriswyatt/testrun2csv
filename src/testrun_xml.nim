import hashes
import streams
import strutils
import tables
import xmlparser
import xmltree

import testrun_shared

const ordPeriod = ord('.')
const ordZero = ord('0')
const ordNine = ord('9')
const ordAUpper = ord('A')
const ordZUpper = ord('Z')
const ordUnderscore = ord('_')
const ordALower = ord('a')
const ordZLower = ord('z')

proc getRoot(filePath: string): XmlNode =
    let stream = newFileStream(filePath, fmRead)
    result = parseXml(stream)
    stream.close()

proc getStatus(statusStr: string): Status =
    result = statusSeq[find(statusStrSeq, statusStr)]

proc parseTest(node: XmlNode): (string, Status, string) =
    let name = node.attr("name")

    let statusStr = node.attr("status")
    let status = getStatus(statusStr)

    let locationUrl = node.attr("locationUrl")

    result = (name, status, locationUrl)

proc parseSuite(node: XmlNode, parents = newSeq[Suite]()): seq[Test] =
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
            let (testName,
                 testStatus,
                 testLocationUrl) = parseTest(child)

            result.add(Test(
                name: testName,
                status: testStatus,
                locationUrl: testLocationUrl,
                suites: parents & @[suite],
            ))
        elif child.tag == "suite":
            for test in parseSuite(child, parents=parents & @[suite]):
                result.add(test)

proc parseRoot(root: XmlNode): (
        int,
        CountTableRef[Status],
        seq[Test],
) =
    var testSeq = newSeq[Test]()

    var numTests: int
    let statusCounts = newCountTable[Status](
        initialSize = statusTableSize,
    )

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
                    raise newException(
                        ValueError,
                        "Duplicate 'count' elements",
                    )

                statusCounts[status] = parseInt(countValueStr)

    return (numTests, statusCounts, testSeq)

proc isNameValid(name: string): bool =
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

proc validate(
        expectedNumTests: int,
        expectedStatusCounts: CountTableRef[Status],
        testSeq: seq[Test],
) =
    let actualStatusCounts = newCountTable[Status](
        initialSize = statusTableSize,
    )

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

    let testHashCounts = newCountTable[Hash](
        initialSize = actualNumTests.rightSize,
    )
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

proc parseFile*(inFilePath: string): seq[Test] =
    let root = getRoot(inFilePath)
    let (numTests, statusCounts, testSeq) = parseRoot(root)
    validate(numTests, statusCounts, testSeq)
    return testSeq
