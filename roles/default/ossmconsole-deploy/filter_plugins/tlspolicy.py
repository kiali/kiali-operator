from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

ANSIBLE_METADATA = {
  'metadata_version': '1.1',
  'status': ['preview'],
  'supported_by': 'community'
}

# Resolve the OpenShift cluster TLS security profile (spec.tlsSecurityProfile of
# APIServer/cluster) into nginx TLS directives for the OSSM Console plugin.
#
# The rules deliberately mirror the Kiali server's TLS policy resolver
# (tlspolicy/resolver.go): an absent profile means Intermediate, TLS 1.0/1.1
# minimums are rejected, cipher-string selectors are rejected, DHE suites are
# skipped, and under a TLS 1.3 minimum the cipher list is ignored.
#
# The operator cannot probe the image's OpenSSL, so availability is
# table-driven: a cipher or group name is "available" when it appears in the
# pinned OpenShift preset table or the TLSGroup enum below. Groups render with
# '?' prefixes so nginx silently skips any group the runtime (for example a
# FIPS host) lacks, rather than failing to start; the tradeoff is that an
# unavailable group is skipped silently instead of being detected and logged,
# and under FIPS the X25519MLKEM768 hybrid quietly disappears from the
# negotiated set.

# Pinned copy of the OpenShift TLS profile definitions
# (github.com/openshift/api config/v1/types_tlssecurityprofile.go) at the
# revision the Kiali server pins. Never fetched at runtime; bump via review.
OPENSHIFT_API_REVISION = 'v0.0.0-20260605005319-1194f4c62539'

VERSION_TLS10 = 'VersionTLS10'
VERSION_TLS11 = 'VersionTLS11'
VERSION_TLS12 = 'VersionTLS12'
VERSION_TLS13 = 'VersionTLS13'

# The only TLS 1.3 suites ever rendered, in OpenShift profile order.
TLS13_SUITES = ('TLS_AES_128_GCM_SHA256', 'TLS_AES_256_GCM_SHA384', 'TLS_CHACHA20_POLY1305_SHA256')

# TLS 1.3 suites OpenSSL knows but the OpenShift profiles never permit.
OTHER_TLS13_SUITES = frozenset(('TLS_AES_128_CCM_SHA256', 'TLS_AES_128_CCM_8_SHA256', 'TLS_SHA256_SHA256', 'TLS_SHA384_SHA384'))

# Every OpenShift TLSGroup enum value.
TLS_GROUPS = ('X25519', 'secp256r1', 'secp384r1', 'secp521r1', 'X25519MLKEM768', 'SecP256r1MLKEM768', 'SecP384r1MLKEM1024')

_GROUP_SPELLING = dict((g.lower(), g) for g in TLS_GROUPS)

_PRESET_GROUPS = ('X25519MLKEM768', 'X25519', 'secp256r1', 'secp384r1')

# cipher names: OpenSSL spelling -> OpenSSL spelling (canonical), plus the
# IANA aliases the Kiali resolver translates. Only names that appear in the
# OpenShift preset tables are considered known; everything else is skipped
# with a warning. DES-CBC3-SHA is excluded because modern OpenSSL removed it.
_CIPHER_ALIASES = {
  'ECDHE-ECDSA-AES128-GCM-SHA256': 'ECDHE-ECDSA-AES128-GCM-SHA256',
  'TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256': 'ECDHE-ECDSA-AES128-GCM-SHA256',
  'ECDHE-RSA-AES128-GCM-SHA256': 'ECDHE-RSA-AES128-GCM-SHA256',
  'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256': 'ECDHE-RSA-AES128-GCM-SHA256',
  'ECDHE-ECDSA-AES256-GCM-SHA384': 'ECDHE-ECDSA-AES256-GCM-SHA384',
  'TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384': 'ECDHE-ECDSA-AES256-GCM-SHA384',
  'ECDHE-RSA-AES256-GCM-SHA384': 'ECDHE-RSA-AES256-GCM-SHA384',
  'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384': 'ECDHE-RSA-AES256-GCM-SHA384',
  'ECDHE-ECDSA-CHACHA20-POLY1305': 'ECDHE-ECDSA-CHACHA20-POLY1305',
  'TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256': 'ECDHE-ECDSA-CHACHA20-POLY1305',
  'ECDHE-RSA-CHACHA20-POLY1305': 'ECDHE-RSA-CHACHA20-POLY1305',
  'TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256': 'ECDHE-RSA-CHACHA20-POLY1305',
  'ECDHE-ECDSA-AES128-SHA256': 'ECDHE-ECDSA-AES128-SHA256',
  'ECDHE-RSA-AES128-SHA256': 'ECDHE-RSA-AES128-SHA256',
  'ECDHE-ECDSA-AES128-SHA': 'ECDHE-ECDSA-AES128-SHA',
  'ECDHE-RSA-AES128-SHA': 'ECDHE-RSA-AES128-SHA',
  'ECDHE-ECDSA-AES256-SHA384': 'ECDHE-ECDSA-AES256-SHA384',
  'ECDHE-RSA-AES256-SHA384': 'ECDHE-RSA-AES256-SHA384',
  'ECDHE-ECDSA-AES256-SHA': 'ECDHE-ECDSA-AES256-SHA',
  'ECDHE-RSA-AES256-SHA': 'ECDHE-RSA-AES256-SHA',
  'AES128-GCM-SHA256': 'AES128-GCM-SHA256',
  'TLS_RSA_WITH_AES_128_GCM_SHA256': 'AES128-GCM-SHA256',
  'AES256-GCM-SHA384': 'AES256-GCM-SHA384',
  'TLS_RSA_WITH_AES_256_GCM_SHA384': 'AES256-GCM-SHA384',
  'AES128-SHA256': 'AES128-SHA256',
  'AES256-SHA256': 'AES256-SHA256',
  'AES128-SHA': 'AES128-SHA',
  'AES256-SHA': 'AES256-SHA',
}

# OpenSSL cipher-string selector words (compared case-insensitively). A
# selector would silently broaden the policy, so any of these makes the
# profile invalid even when mixed with usable suite names.
_SELECTORS = frozenset(s.upper() for s in (
  'ALL', 'DEFAULT', 'COMPLEMENTOFALL', 'COMPLEMENTOFDEFAULT',
  'HIGH', 'MEDIUM', 'LOW',
  'aNULL', 'eNULL', 'NULL', 'kANON',
  'kRSA', 'kEDH', 'kDHE', 'kECDHE', 'kEECDH', 'kPSK', 'kSRP', 'kGOST',
  'ECDHE', 'ECDSA', 'RSA', 'DHE', 'EDH', 'ADH', 'AECDH', 'SHA', 'SHA256', 'SHA384',
  'AES', 'AES128', 'AES256', 'AESGCM', 'CHACHA20', '3DES', 'DES', 'RC4', 'MD5',
  'SSLv3', 'TLSv1', 'TLSv1.2', 'TLSv1.3', 'FIPS',
))

_PRESETS = {
  'Old': {
    'ciphers': (
      'TLS_AES_128_GCM_SHA256', 'TLS_AES_256_GCM_SHA384', 'TLS_CHACHA20_POLY1305_SHA256',
      'ECDHE-ECDSA-AES128-GCM-SHA256', 'ECDHE-RSA-AES128-GCM-SHA256',
      'ECDHE-ECDSA-AES256-GCM-SHA384', 'ECDHE-RSA-AES256-GCM-SHA384',
      'ECDHE-ECDSA-CHACHA20-POLY1305', 'ECDHE-RSA-CHACHA20-POLY1305',
      'ECDHE-ECDSA-AES128-SHA256', 'ECDHE-RSA-AES128-SHA256',
      'ECDHE-ECDSA-AES128-SHA', 'ECDHE-RSA-AES128-SHA',
      'ECDHE-ECDSA-AES256-SHA384', 'ECDHE-RSA-AES256-SHA384',
      'ECDHE-ECDSA-AES256-SHA', 'ECDHE-RSA-AES256-SHA',
      'AES128-GCM-SHA256', 'AES256-GCM-SHA384',
      'AES128-SHA256', 'AES256-SHA256', 'AES128-SHA', 'AES256-SHA',
      'DES-CBC3-SHA',
    ),
    'groups': _PRESET_GROUPS,
    'min_tls_version': VERSION_TLS10,
  },
  'Intermediate': {
    'ciphers': (
      'TLS_AES_128_GCM_SHA256', 'TLS_AES_256_GCM_SHA384', 'TLS_CHACHA20_POLY1305_SHA256',
      'ECDHE-ECDSA-AES128-GCM-SHA256', 'ECDHE-RSA-AES128-GCM-SHA256',
      'ECDHE-ECDSA-AES256-GCM-SHA384', 'ECDHE-RSA-AES256-GCM-SHA384',
      'ECDHE-ECDSA-CHACHA20-POLY1305', 'ECDHE-RSA-CHACHA20-POLY1305',
    ),
    'groups': _PRESET_GROUPS,
    'min_tls_version': VERSION_TLS12,
  },
  'Modern': {
    'ciphers': ('TLS_AES_128_GCM_SHA256', 'TLS_AES_256_GCM_SHA384', 'TLS_CHACHA20_POLY1305_SHA256'),
    'groups': _PRESET_GROUPS,
    'min_tls_version': VERSION_TLS13,
  },
}

_VERSIONS = {
  '': 'TLSv1.2', 'TLSv1.2': 'TLSv1.2', 'TLS1.2': 'TLSv1.2', VERSION_TLS12: 'TLSv1.2',
  'TLSv1.3': 'TLSv1.3', 'TLS1.3': 'TLSv1.3', VERSION_TLS13: 'TLSv1.3',
}
_REJECTED_VERSIONS = {
  'TLSv1.0': '1.0', 'TLS1.0': '1.0', VERSION_TLS10: '1.0',
  'TLSv1.1': '1.1', 'TLS1.1': '1.1', VERSION_TLS11: '1.1',
}

# The injection barrier: nothing outside this grammar reaches the rendered config.
_TOKEN_RE_CHARS = frozenset('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-')


def _invalid(reason):
  return {'valid': False, 'reason': reason, 'directives': [], 'warnings': [], 'profile': ''}


def _valid(name, directives, warnings):
  return {'valid': True, 'reason': '', 'directives': directives, 'warnings': warnings, 'profile': name}


_TOKEN_FIRST_CHARS = frozenset('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789')


def _well_formed(token):
  return bool(token) and token[0] in _TOKEN_FIRST_CHARS and all(c in _TOKEN_RE_CHARS for c in token)


def _render(protocols, tls12_ciphers, groups):
  lines = ['ssl_protocols ' + ' '.join(protocols) + ';']
  if tls12_ciphers:
    lines.append('ssl_ciphers ' + ':'.join(tls12_ciphers) + ';')
  lines.append('ssl_conf_command Ciphersuites ' + ':'.join(TLS13_SUITES) + ';')
  if groups is not None:
    # '?' prefixes: nginx skips a group the runtime lacks instead of failing to start.
    lines.append('ssl_ecdh_curve ' + ':'.join('?' + g for g in groups) + ';')
  return lines


def _resolve_tls12(ciphers, warnings):
  """Return (retained TLS 1.2 suite names in order, whether a standard TLS 1.3 name was listed)."""
  upper13 = set(TLS13_SUITES)
  listed_tls13 = False
  tokens = []
  for name in ciphers:
    if name.upper() in upper13:
      listed_tls13 = True
      continue
    if name.upper() in OTHER_TLS13_SUITES:
      warnings.append('skipping TLS 1.3 suite outside the permitted set: ' + name)
      continue
    tokens.append(name)
  for token in tokens:
    if token.upper() in _SELECTORS:
      raise _ProfileError('cipher list contains cipher-string selector ' + token + '; only individual suite names are accepted')
  retained = []
  for token in tokens:
    upper = token.upper()
    if upper.startswith(('DHE-', 'EDH-')) or '_DHE_' in upper:
      warnings.append('skipping DHE cipher (no ssl_dhparam is configured): ' + token)
      continue
    canonical = _CIPHER_ALIASES.get(token) or _CIPHER_ALIASES.get(upper)
    if canonical is None:
      warnings.append('skipping cipher not in the supported table: ' + token)
      continue
    if canonical not in retained:
      retained.append(canonical)
  return retained, listed_tls13


class _ProfileError(Exception):
  pass


def resolve_tls_profile(profile):
  """Resolve spec.tlsSecurityProfile (None when absent) into nginx directives.

  Returns a dict: valid (bool), reason (str), directives (list of nginx
  directive lines), warnings (list of str), profile (display name).
  """
  try:
    return _resolve(profile)
  except _ProfileError as exc:
    return _invalid(str(exc))


def _resolve(profile):
  warnings = []
  if profile is None:
    preset = _PRESETS['Intermediate']
    return _resolve_preset('Intermediate (default)', preset, warnings)

  if not isinstance(profile, dict):
    return _invalid('spec.tlsSecurityProfile must be an object')

  ptype = profile.get('type')
  if isinstance(ptype, str) and ptype in _PRESETS:
    if ptype == 'Old':
      return _invalid('profile Old requires a TLS 1.0 minimum; OSSMC does not support TLS versions below 1.2')
    return _resolve_preset(ptype, _PRESETS[ptype], warnings)

  if ptype == 'Custom':
    custom = profile.get('custom')
    if custom is None:
      return _invalid('custom TLS profile specified but the custom field is missing or null')
    if not isinstance(custom, dict):
      return _invalid('spec.tlsSecurityProfile.custom must be an object')
    ciphers = custom.get('ciphers')
    groups = custom.get('groups')
    min_version = custom.get('minTLSVersion')
    if min_version is None:
      min_version = ''
    if not isinstance(min_version, str):
      return _invalid('custom.minTLSVersion must be a string')
    for field, value in (('ciphers', ciphers), ('groups', groups)):
      if value is not None and (not isinstance(value, list) or not all(isinstance(v, str) for v in value)):
        return _invalid('custom.' + field + ' must be a list of strings')
    return _resolve_custom(ciphers, groups, min_version, warnings)

  shown = ptype if isinstance(ptype, str) else ('' if ptype is None else repr(ptype))
  return _invalid('unknown TLS profile type: [' + shown + ']')


def _resolve_preset(name, preset, warnings):
  if preset['min_tls_version'] == VERSION_TLS13:
    return _valid(name, _render(('TLSv1.3',), (), preset['groups']), warnings)
  ciphers = [c for c in preset['ciphers'] if c not in TLS13_SUITES and c != 'DES-CBC3-SHA']
  if 'DES-CBC3-SHA' in preset['ciphers']:
    warnings.append('skipping cipher not in the supported table: DES-CBC3-SHA')
  return _valid(name, _render(('TLSv1.2', 'TLSv1.3'), ciphers, preset['groups']), warnings)


def _resolve_custom(ciphers, groups, min_version, warnings):
  version = min_version.strip()
  if version in _REJECTED_VERSIONS:
    return _invalid('profile requires a TLS ' + _REJECTED_VERSIONS[version] +
                    ' minimum; OSSMC does not support TLS versions below 1.2')
  if version not in _VERSIONS:
    return _invalid('unknown TLS version [' + min_version + ']; supported versions are TLSv1.2 and TLSv1.3')
  min_version = _VERSIONS[version]

  # Groups: omitted or empty means "no opinion" (no directive); the grammar
  # check runs before anything else so nothing malformed reaches the config.
  resolved_groups = None
  if groups:
    for g in groups:
      if not _well_formed(g):
        return _invalid('malformed group entries ' + repr(groups) + '; each must match [A-Za-z0-9][A-Za-z0-9_-]*')
    resolved_groups = []
    for g in groups:
      spelling = _GROUP_SPELLING.get(g.lower())
      if spelling is None:
        warnings.append('skipping group that is not an OpenShift TLS group: ' + g)
        continue
      if spelling not in resolved_groups:
        resolved_groups.append(spelling)
    if not resolved_groups:
      return _invalid('no usable TLS groups remain from list ' + repr(groups))

  if min_version == 'TLSv1.3':
    # Cipher entries do not apply under a TLS 1.3 minimum; never validated, never rendered.
    if ciphers:
      warnings.append('TLS 1.2 ciphers do not apply under a TLS 1.3 minimum; ignoring the profile cipher list')
    return _valid('Custom', _render(('TLSv1.3',), (), resolved_groups), warnings)

  if not ciphers:
    ciphers = [c for c in _PRESETS['Intermediate']['ciphers'] if c not in TLS13_SUITES]
    warnings.append('custom profile lists no ciphers; using the Intermediate TLS 1.2 suites')

  for c in ciphers:
    if not _well_formed(c):
      return _invalid('malformed cipher entries ' + repr(ciphers) + '; each must match [A-Za-z0-9][A-Za-z0-9_-]*')

  try:
    retained, listed_tls13 = _resolve_tls12(ciphers, warnings)
  except _ProfileError as exc:
    return _invalid(str(exc))

  if retained:
    return _valid('Custom', _render(('TLSv1.2', 'TLSv1.3'), retained, resolved_groups), warnings)
  if listed_tls13:
    warnings.append('no TLS 1.2 suite remains; TLS 1.2 is disabled and only TLS 1.3 is served')
    return _valid('Custom', _render(('TLSv1.3',), (), resolved_groups), warnings)
  return _invalid('no usable TLS cipher suites found from list ' + repr(ciphers) +
                  ' (DHE, unknown and unsupported suites are skipped)')


# ---- Ansible filters ----
class FilterModule(object):
  def filters(self):
    return {
      'resolve_tls_profile': resolve_tls_profile
    }
