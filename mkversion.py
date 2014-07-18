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

if os.access('.git', os.F_OK):
    git_hash = run_command(['git', 'rev-parse', 'HEAD']).strip()
    git_diff = run_command(['git', 'diff', '--numstat']).strip()
    git_hash = git_hash[:6]
    if git_diff:
        git_hash += '+'
else:
    git_hash = None

if git_hash:
    version_string = '%s git %s' % (date_str, git_hash)
else:
    version_string = '%s' % (date_str,)

fd = open("version.s", 'w')
fd.write('; do not modify -- dynamically generated file\n')
fd.write('\n')
fd.write('\t.module version\n')
fd.write('\t.globl _software_version_string\n')
fd.write('\t.area _CODE\n\n')
fd.write('_software_version_string:\n')
fd.write('\t.ascii "UNA CP/M (Will Sowerbutts, %s)"\n' % version_string)
fd.write('\t.db 0\n')
