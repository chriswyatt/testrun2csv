import argparse

import testrun_csv
import testrun_xml

proc parseArgs: string =
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

let testSeq = parseFile(inFilePath)
writeCsv(testSeq)
