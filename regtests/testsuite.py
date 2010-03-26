#!/usr/bin/env gnatpython
"""./testsuite.py [options] [test name]

Run the templates_parser testsuite
"""

from gnatpython.env import Env
from gnatpython.ex import Run
from gnatpython.fileutils import mkdir, rm
from gnatpython.main import Main
from gnatpython.mainloop import (MainLoop, add_mainloop_options,
                                 generate_collect_result)
from gnatpython.testdriver import add_run_test_options
from gnatpython.reports import ReportDiff

from glob import glob

import os
import sys

#  Compute PATH to global test drivers (testme, print_tree)

PLATFORM = os.environ.get("PLATFORM")
PRJ_BUILD = os.environ.get("PRJ_BUILD")

if PLATFORM == None:
    PLATFORM = "native"
else:
    PLATFORM = PLATFORM.lower()

if PRJ_BUILD == None:
    PRJ_BUILD = "debug"
else:
    PRJ_BUILD = PRJ_BUILD.lower()

ep = os.getcwd() + "/../.build/" + PLATFORM + "/" + PRJ_BUILD + "/static/"

os.environ["PATH"] = os.environ.get("PATH") + os.pathsep + ep \
        + "bin" + os.pathsep + ep + "rbin"

from gnatpython.ex import Run


def gnatmake(prj):
    """Compile a project with gnatmake"""
    cmd = ["gnatmake", "-p", "-gnat05", "-P" + prj, "-bargs", "-E"]
    process = Run(cmd)
    if process.status:
        print process.out


def main():
    """Run the testsuite"""
    options = __parse_options()
    env = Env()
    env.add_search_path("PYTHONPATH", os.getcwd())

    test_list = [t for t in filter_list('tests/*', options.run_test)
                 if os.path.isdir(t)]

    # Various files needed or created by the testsuite
    result_dir = options.output_dir
    results_file = result_dir + '/results'

    if os.path.exists(result_dir):
        for file in (results_file, result_dir + '/report', 'discs'):
            rm(file, True)
        for ext in ('.diff', '.expected', '.out', '.result'):
            for file in glob(result_dir + '/*' + ext):
                rm(file, True)
    mkdir(result_dir)

    discs = ['ALL']
    discs.append('ALL')
    discs.append(env.target.platform)
    discs.append(env.target.triplet)

    if options.discs:
        discs += options.discs

    def test_build_cmd(test, _):
        """Run the given test"""
        cmd = [sys.executable, 'run-test',
                    '-d', ",".join(discs),
                    '-o', result_dir,
                    '-t', options.tmp,
                    test]
        if options.verbose:
            cmd.append('-v')
        if options.host:
            cmd.append('--host=' + options.host)
        if options.target:
            cmd.append('--target=' + options.target)
        if not options.enable_cleanup:
            cmd.append('--disable-cleanup')
        return Run(cmd, bg=True)

    collect_result = generate_collect_result(
        result_dir, results_file, options.view_diffs)

    MainLoop(test_list, test_build_cmd, collect_result, options.mainloop_jobs)

    # Write report
    with open(result_dir + '/discs', 'w') as discs_f:
        discs_f.write(" ".join(discs))
    ReportDiff(result_dir, options.old_result_dir).txt_image(
        result_dir + '/report')


def filter_list(pattern, run_test=""):
    """Compute the list of test matching pattern

    If run_test is not null, run only tests containing run_test
    """
    test_list = glob(pattern)
    if not run_test:
        return test_list
    else:
        return [test for test in test_list if run_test in test]


def __parse_options():
    """Parse command lines options"""
    m = Main()
    add_mainloop_options(m)
    add_run_test_options(m)
    m.add_option("--diffs", dest="view_diffs", action="store_true",
                 default=False, help="Print .diff content")
    m.add_option("--old-result-dir", type="string", default=None,
                 help="Old result dir")
    m.parse_args()

    if m.args:
        m.options.run_test = m.args[0]
        # User want to run only one test
        print "Running only test '%s'" % m.options.run_test
    else:
        m.options.run_test = ""

    if m.options.discs:
        m.options.discs = m.options.discs.split(',')

    return m.options

if __name__ == "__main__":
    try:
        main()
    except AssertionError, e:
        print 'ERROR: %s' % e
