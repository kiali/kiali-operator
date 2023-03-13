from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

ANSIBLE_METADATA = {
  'metadata_version': '1.1',
  'status': ['preview'],
  'supported_by': 'community'
}

import re

# Given a list of all known namespaces (value) and a list of accessible namespace regular expressions,
# filter out all non-accessible namespaces (i.e. return a list of only the namespaces that match an accessible namespace regex).
def only_accessible_namespaces(value, accessible_namespaces=[]):

  # cache the regex patterns for speed
  accessible_namespace_regex_patterns = []
  for accessible_namespace_regex in accessible_namespaces:
    accessible_namespace_regex_patterns.append(re.compile('^' + accessible_namespace_regex + '$'))

  all_accessible_namespaces = []
  for namespace in value:
    for p in accessible_namespace_regex_patterns:
      if re.match(p, namespace):
        all_accessible_namespaces.append(namespace)
        break
  return all_accessible_namespaces

# ---- Ansible filters ----
class FilterModule(object):
  def filters(self):
    return {
      'only_accessible_namespaces': only_accessible_namespaces
    }
