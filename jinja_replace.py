#!/usr/bin/python

import os
import sys
from jinja2 import Environment, BaseLoader

with open(sys.argv[1], 'r') as file:
    template = file.read()

expected_keys = []

full_env = os.environ.copy()
filtered_env = { key : full_env[key] for key in full_env if ( key.startswith("LDIF_REPLACE_") or key in expected_keys )}
rtemplate = Environment(loader=BaseLoader()).from_string(template)
result = rtemplate.render(**filtered_env)

print result
