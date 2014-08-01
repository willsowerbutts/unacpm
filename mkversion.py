#!/usr/bin/env python

import os
import subprocess
import datetime

def run_command(cmd):
    pr = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    out, err = pr.communicate()

    if pr.returncode:
        raise RuntimeError('command %r failed with code %r' % (cmd, pr.returncode))

    return out

date_str = datetime.datetime.now().strftime("%Y-%m-%d")
version_string = date_str

git_hash = None
if os.access('.git', os.F_OK):
    # for my development versions
    try:
        git_hash = run_command(['git', 'rev-parse', 'HEAD']).strip()
        git_diff = run_command(['git', 'diff', '--numstat']).strip()
        git_hash = git_hash[:6]
        if git_diff:
            git_hash += '+'
        version_string = '%s git %s' % (date_str, git_hash)
        # write a file that is used by release versions
        open("version.num", 'w').write(version_string)
    except Exception, e:
        print "Git failed or not installed: %s" % str(e)
else:
    # for release versions
    if os.access('version.num', os.R_OK):
        version_string = open('version.num').read()

open("version.s", 'w').write(
"""; do not modify -- dynamically generated file

	.module version
	.globl _software_version_string
	.area _CODE

_software_version_string:
	.ascii "UNA CP/M (Will Sowerbutts, %s)"
	.db 0
""" % version_string)
