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

git_hash = None
if os.access('.git', os.F_OK):
    try:
        git_hash = run_command(['git', 'rev-parse', 'HEAD']).strip()
        git_diff = run_command(['git', 'diff', '--numstat']).strip()
        git_hash = git_hash[:6]
        if git_diff:
            git_hash += '+'
    except Exception, e:
        print "Git failed or not installed: %s" % str(e)

if git_hash:
    version_string = '%s git %s' % (date_str, git_hash)
else:
    version_string = '%s' % (date_str,)

open("version.s", 'w').write(
"""; do not modify -- dynamically generated file

	.module version
	.globl _software_version_string
	.area _CODE

_software_version_string:
	.ascii "UNA CP/M (Will Sowerbutts, %s)"
	.db 0
""" % version_string)
