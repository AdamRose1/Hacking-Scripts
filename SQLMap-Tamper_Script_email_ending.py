#!/usr/bin/env python

"""
I created this tamper script so that sqlmap will work on an email input that has a regex filter that requires an ending of @anything.com.  By using this tamper script, sqlmap will put '@test.com' at the end of each payload it sends.  This way the request sqlmap sends will go through successfully.
Place this python tamper script in /usr/share/sqlmap/tamper/ and then run sqlmap with --tamper=name-of-this-file
"""

import os

from lib.core.enums import PRIORITY

__priority__ = PRIORITY.LOWEST

def dependencies():
    pass

def tamper(payload, **kwargs):
    return payload + '@test.com'  # adds @test.com to the end of each payload
