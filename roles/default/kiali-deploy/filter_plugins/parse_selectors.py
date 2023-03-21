from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

from ansible.errors import AnsibleFilterError

ANSIBLE_METADATA = {
  'metadata_version': '1.1',
  'status': ['preview'],
  'supported_by': 'community'
}

# Given a list of label selectors in the standard k8s format, convert to the format that the k8s ansible collection wants.
# For example, given this input:
# - matchLabels:
#     foo: bar
# - matchLabels:
#     color: blue
#   matchExpressions:
#   - key: region
#     operator: In
#     values:
#     - east
#     - west
# an array will be returned with two items.
# The first is a list with one item that is "foo=bar".
# The second is a list with two items. The first item being "color=blue" and the second item being "region in (east, west)"
#
# See:
# * https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#label-selectors
# * https://docs.ansible.com/ansible/latest/collections/kubernetes/core/k8s_info_module.html#parameter-label_selectors
def parse_selectors(value):
  # these are the selectors that should be OR'ed together - this is the final result returned back from this function
  selectorOr = []
  selectorOrIndex = 0

  # for each item in the selectors list, there can be one matchLabels and one matchExpressions (both can be there, or just one of them).
  for selectors in value:
    selectorOr.append([])

    # process the matchLabels - each results in "labelName=labelValue" strings
    if "matchLabels" in selectors:
      if (selectors["matchLabels"] is None) or (len(selectors["matchLabels"]) == 0):
        raise AnsibleFilterError("Selector matchLabels is empty")
      for k, v in selectors["matchLabels"].items():
        expr = k + "=" + v
        selectorOr[selectorOrIndex].append(expr)

    # process the matchExpressions - each results in something like "labelName notin (labelValue, labelValue2)"
    if "matchExpressions" in selectors:
      for me in selectors["matchExpressions"]:
        if "key" not in me:
          raise AnsibleFilterError("Selector matchExpression is missing 'key'")
        key = me["key"]

        if "operator" not in me:
          raise AnsibleFilterError("Selector matchExpression is missing 'operator'")
        operator = me["operator"].lower()

        if (operator == "in" or operator == "notin") and ("values" not in me or me["values"] is None or (len(me["values"]) == 0)):
          raise AnsibleFilterError("Selector matchExpression is missing a non-empty 'values'")
        values = me["values"] if "values" in me else []
        valuesStr = "("
        for i, v in enumerate(values):
          if i > 0:
            valuesStr += ","
          valuesStr += v
        valuesStr += ")"

        if operator == "in":
          selectorOr[selectorOrIndex].append(key + " in " + valuesStr)
        elif operator == "notin":
          selectorOr[selectorOrIndex].append(key + " notin " + valuesStr)
        elif operator == "exists":
          selectorOr[selectorOrIndex].append(key)
        elif operator == "doesnotexist":
          selectorOr[selectorOrIndex].append("!" + key)
        else:
          raise AnsibleFilterError("Selector matchExpression has invalid operator: " + operator)

    selectorOrIndex = selectorOrIndex + 1

  return selectorOr

# ---- Ansible filters ----
class FilterModule(object):
  def filters(self):
    return {
      'parse_selectors': parse_selectors
    }

# TEST
#first = {
#  "matchLabels":      { "sport": "football", "region": "west" },
#  "matchExpressions": [{ "key": "region", "operator": "In", "values": ["east" ]}, { "key": "sport", "operator": "Exists"}]
#}
#second = {
#  "matchLabels":      { "region": "east", "sport": "golf" },
#}
#third = {
#  "matchExpressions": [{ "key": "sport", "operator": "In", "values": ["baseball", "football" ]},{ "key": "region", "operator": "NotIn", "values": ["east" ]}]
#}
#fourth = {
#  "matchExpressions": [{ "key": "sport", "operator": "NotIn", "values": ["baseball", "football" ]},{ "key": "region", "operator": "Exists"},{ "key": "foo", "operator": "DoesNotExist"}]
#}
#print ("The following should be successful:")
#print (parse_selectors([first, second, third, fourth]))
#print ("The following should result in an error:")
#print (parse_selectors([{"matchExpressions": [{ "key": "sport", "operator": "XIn"}]}]))
