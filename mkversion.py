#!/usr/bin/env python

import os
import subprocess
import datetime

date_str = datetime.datetime.now().strftime("%Y-%m-%d")

if os.access('.git', os.F_OK):
    pr = subprocess.Popen(['git', 'rev-parse', 'HEAD'], stdout=subprocess.PIPE)
    git_hash, err = pr.communicate()

    if pr.returncode:
        raise RuntimeError, 'git failed'

    git_hash = git_hash.strip()
else:
    git_hash = None

if git_hash:
    version_string = '%s git %s' % (date_str, git_hash[:6])
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
