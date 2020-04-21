import argparse
import sequtils
import streams
import xmlparser
import xmltree

type
    Status = enum
        error, failed, ignored, passed

const statusSeq = @[error, failed, ignored, passed]
const statusStrSeq = @["error", "failed", "ignored", "passed"]

type
    Test = object
        name*: string
        status*: Status

type
    Suite = object
        name*: string
        status*: Status
        tests*: seq[Test]

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
    result = Test(name: name, status: status)

proc parseSuite(node : XmlNode) : Suite =
    let name = node.attr("name")
    let statusStr = node.attr("status")
    let status = getStatus(statusStr)

    var testSeq = newSeq[Test]()

    for child in node:
        if child.tag == "test":
            testSeq.add(parseTest(child))

    result = Suite(name: name, status: status, tests: testSeq)

proc parseRoot(root : XmlNode) : seq[Suite] =
    result = newSeq[Suite]()

    for child in root:
        if child.tag == "suite":
            result.add(parseSuite(child))

proc main() =
    let p = newParser("testrun_parse"):
        help("Parse IntelliJ testrun XML files")
        arg(
            "in_file",
            help = "Input file",
        )

    var inFilePath : string

    try:
        let opts = p.parse()
        inFilePath = opts.in_file
    except UsageError:
        p.run(@["--help"])
        return

    let root = getRoot(inFilePath)
    let suiteSeq = parseRoot(root)
    echo $suiteSeq

main()
