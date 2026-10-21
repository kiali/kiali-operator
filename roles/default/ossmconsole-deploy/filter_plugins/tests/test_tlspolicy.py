"""Unit tests for the tlspolicy filter plugin.

Plain unittest, no Ansible required: run with
  python3 -m unittest discover -s roles/default/ossmconsole-deploy/filter_plugins/tests
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tlspolicy import (  # noqa: E402
    OPENSHIFT_API_REVISION,
    TLS13_SUITES,
    TLS_GROUPS,
    _PRESETS,
    resolve_tls_profile,
)


def custom(ciphers=None, groups=None, min_version=None, **extra):
    body = dict(extra)
    if ciphers is not None:
        body['ciphers'] = ciphers
    if groups is not None:
        body['groups'] = groups
    if min_version is not None:
        body['minTLSVersion'] = min_version
    return {'type': 'Custom', 'custom': body}


class ResolveTestCase(unittest.TestCase):
    def resolve(self, profile):
        return resolve_tls_profile(profile)

    def assertInvalid(self, profile, fragment):
        result = self.resolve(profile)
        self.assertFalse(result['valid'], repr(result))
        self.assertIn(fragment, result['reason'])
        self.assertEqual(result['directives'], [])

    def directives(self, profile):
        result = self.resolve(profile)
        self.assertTrue(result['valid'], repr(result))
        return result['directives']


class PresetTableTest(unittest.TestCase):
    def test_golden_table(self):
        """The pinned preset table, asserted exactly (bump via documented review)."""
        self.assertEqual(OPENSHIFT_API_REVISION, 'v0.0.0-20260605005319-1194f4c62539')
        self.assertEqual(TLS_GROUPS, ('X25519', 'secp256r1', 'secp384r1', 'secp521r1',
                                      'X25519MLKEM768', 'SecP256r1MLKEM768', 'SecP384r1MLKEM1024'))
        self.assertEqual(_PRESETS['Old']['min_tls_version'], 'VersionTLS10')
        self.assertEqual(_PRESETS['Intermediate']['min_tls_version'], 'VersionTLS12')
        self.assertEqual(_PRESETS['Modern']['min_tls_version'], 'VersionTLS13')
        for name in ('Old', 'Intermediate', 'Modern'):
            self.assertEqual(_PRESETS[name]['groups'],
                             ('X25519MLKEM768', 'X25519', 'secp256r1', 'secp384r1'), name)
        self.assertEqual(_PRESETS['Modern']['ciphers'], TLS13_SUITES)
        self.assertEqual(len(_PRESETS['Intermediate']['ciphers']), 9)
        self.assertEqual(len(_PRESETS['Old']['ciphers']), 24)
        self.assertIn('DES-CBC3-SHA', _PRESETS['Old']['ciphers'])


class PresetsTest(ResolveTestCase):
    def test_absent_profile_is_intermediate(self):
        d = self.directives(None)
        self.assertEqual(d, [
            'ssl_protocols TLSv1.2 TLSv1.3;',
            'ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:'
            'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:'
            'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;',
            'ssl_conf_command Ciphersuites ' + ':'.join(TLS13_SUITES) + ';',
            'ssl_ecdh_curve ?X25519MLKEM768:?X25519:?secp256r1:?secp384r1;',
        ])

    def test_intermediate_matches_absent(self):
        self.assertEqual(self.directives({'type': 'Intermediate'}),
                         self.directives({'type': 'Intermediate', 'intermediate': {}}))

    def test_modern(self):
        d = self.directives({'type': 'Modern'})
        self.assertEqual(d[0], 'ssl_protocols TLSv1.3;')
        self.assertFalse([line for line in d if line.startswith('ssl_ciphers')])
        self.assertIn('ssl_conf_command Ciphersuites ' + ':'.join(TLS13_SUITES) + ';', d)
        self.assertEqual(d[-1], 'ssl_ecdh_curve ?X25519MLKEM768:?X25519:?secp256r1:?secp384r1;')

    def test_old_rejected(self):
        self.assertInvalid({'type': 'Old'}, 'below 1.2')

    def test_tls_1_3_suites_always_pinned(self):
        for profile in (None, {'type': 'Modern'}, custom(['ECDHE-RSA-AES128-GCM-SHA256'])):
            self.assertIn('ssl_conf_command Ciphersuites ' + ':'.join(TLS13_SUITES) + ';',
                          self.directives(profile))


class CustomShapeTest(ResolveTestCase):
    def test_min_version_spellings(self):
        for spelling in ('VersionTLS12', 'TLSv1.2', 'TLS1.2', ' VersionTLS12 '):
            self.assertIn('ssl_protocols TLSv1.2 TLSv1.3;',
                          self.directives(custom(['ECDHE-RSA-AES128-GCM-SHA256'], min_version=spelling)), spelling)
        for spelling in ('VersionTLS13', 'TLSv1.3', 'TLS1.3'):
            self.assertEqual('ssl_protocols TLSv1.3;',
                             self.directives(custom(None, min_version=spelling))[0], spelling)

    def test_empty_min_version_is_tls12(self):
        self.assertIn('ssl_protocols TLSv1.2 TLSv1.3;',
                      self.directives(custom(['ECDHE-RSA-AES128-GCM-SHA256'], min_version='')))

    def test_rejected_versions(self):
        for spelling in ('VersionTLS10', 'TLSv1.0', 'TLS1.0', 'VersionTLS11', 'TLSv1.1', 'TLS1.1'):
            self.assertInvalid(custom(['ECDHE-RSA-AES128-GCM-SHA256'], min_version=spelling), 'below 1.2')

    def test_unknown_version(self):
        self.assertInvalid(custom(min_version='VersionTLS14'), 'unknown TLS version')

    def test_null_custom_body(self):
        self.assertInvalid({'type': 'Custom', 'custom': None}, 'missing or null')
        self.assertInvalid({'type': 'Custom'}, 'missing or null')

    def test_wrong_json_types(self):
        self.assertInvalid('Intermediate', 'must be an object')
        self.assertInvalid({'type': 'Custom', 'custom': []}, 'must be an object')
        self.assertInvalid(custom('ECDHE-RSA-AES128-GCM-SHA256'), 'list of strings')
        self.assertInvalid(custom([1, 2]), 'list of strings')
        self.assertInvalid(custom(['ECDHE-RSA-AES128-GCM-SHA256'], 'X25519'), 'list of strings')
        self.assertInvalid({'type': 'Custom', 'custom': {'minTLSVersion': 12}}, 'must be a string')
        self.assertInvalid({'type': 3}, 'unknown TLS profile type')

    def test_unknown_types(self):
        self.assertInvalid({}, 'unknown TLS profile type: []')
        self.assertInvalid({'type': ''}, 'unknown TLS profile type: []')
        self.assertInvalid({'type': 'Paranoid'}, 'unknown TLS profile type: [Paranoid]')


class Tls12RulesTest(ResolveTestCase):
    def test_retained_in_order_and_deduplicated(self):
        d = self.directives(custom(['ECDHE-RSA-AES256-GCM-SHA384', 'ECDHE-RSA-AES128-GCM-SHA256',
                                    'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384']))
        self.assertIn('ssl_ciphers ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256;', d)

    def test_iana_name_normalized(self):
        d = self.directives(custom(['TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256']))
        self.assertIn('ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256;', d)

    def test_dhe_mixed_with_ecdhe_reduced(self):
        result = self.resolve(custom(['DHE-RSA-AES128-GCM-SHA256', 'ECDHE-RSA-AES128-GCM-SHA256']))
        self.assertTrue(result['valid'])
        self.assertIn('ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256;', result['directives'])
        self.assertTrue(any('DHE' in w for w in result['warnings']))

    def test_dhe_only_invalid(self):
        self.assertInvalid(custom(['DHE-RSA-AES128-GCM-SHA256', 'DHE-RSA-AES256-GCM-SHA384']), 'no usable')

    def test_unknown_only_invalid(self):
        self.assertInvalid(custom(['NOT-A-CIPHER', 'ALSO-NOT']), 'no usable')

    def test_unsupported_only_invalid(self):
        self.assertInvalid(custom(['DES-CBC3-SHA', 'RC4-SHA']), 'no usable')

    def test_known_unavailable_and_typos_skipped(self):
        result = self.resolve(custom(['DES-CBC3-SHA', 'ECDHE-RSA-AES128-GCM-SHAZ56', 'ECDHE-RSA-AES128-GCM-SHA256']))
        self.assertTrue(result['valid'])
        self.assertIn('ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256;', result['directives'])
        self.assertTrue(any('not in the supported table' in w for w in result['warnings']))

    def test_empty_custom_list_uses_intermediate(self):
        result = self.resolve(custom([]))
        self.assertTrue(result['valid'])
        self.assertIn('ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:', result['directives'][1])
        self.assertTrue(any('Intermediate' in w for w in result['warnings']))

    def test_omitted_custom_list_uses_intermediate(self):
        result = self.resolve(custom(min_version='VersionTLS12'))
        self.assertTrue(result['valid'])
        self.assertIn('ssl_ciphers', result['directives'][1])

    def test_only_tls13_names_gives_tls13_only(self):
        result = self.resolve(custom(['TLS_AES_128_GCM_SHA256', 'TLS_AES_256_GCM_SHA384'], min_version='VersionTLS12'))
        self.assertTrue(result['valid'])
        self.assertNotIn('ssl_ciphers', ' '.join(result['directives']))
        self.assertEqual(result['directives'][0], 'ssl_protocols TLSv1.3;')
        self.assertTrue(any('TLS 1.2 is disabled' in w for w in result['warnings']))

    def test_dhe_plus_tls13_name_gives_tls13_only(self):
        d = self.directives(custom(['DHE-RSA-AES128-GCM-SHA256', 'TLS_AES_128_GCM_SHA256']))
        self.assertEqual(d[0], 'ssl_protocols TLSv1.3;')

    def test_ccm_never_rendered(self):
        result = self.resolve(custom(['TLS_AES_128_CCM_SHA256', 'ECDHE-RSA-AES128-GCM-SHA256']))
        self.assertTrue(result['valid'])
        self.assertNotIn('CCM', ' '.join(result['directives']))
        self.assertTrue(any('outside the permitted set' in w for w in result['warnings']))


class SelectorTest(ResolveTestCase):
    def test_selectors_rejected(self):
        for selector in ('HIGH', 'ALL', 'DEFAULT', 'aNULL', 'eNULL', 'NULL', 'kRSA', 'CHACHA20', 'AESGCM'):
            self.assertInvalid(custom([selector]), 'selector', )

    def test_selectors_mixed_with_usable_suites_rejected(self):
        self.assertInvalid(custom(['aNULL', 'ECDHE-RSA-AES128-GCM-SHA256']), 'selector')
        self.assertInvalid(custom(['ECDHE-RSA-AES128-GCM-SHA256', 'HIGH']), 'selector')

    def test_grammar_violations(self):
        for bad in ('ECDHE-RSA-AES128-GCM-SHA256;', 'A\nB', 'A"', "A'", 'A:B', '!MD5', '-ECDHE', 'A B', 'A+B', '@STRENGTH'):
            self.assertInvalid(custom([bad]), 'malformed')
            self.assertInvalid(custom(None, [bad], 'VersionTLS13'), 'malformed')


class Tls13MinimumTest(ResolveTestCase):
    def test_selectors_and_garbage_ignored(self):
        result = self.resolve(custom(['HIGH', 'DHE-RSA-AES128-GCM-SHA256', 'bad;value\n', '!x'], None, 'VersionTLS13'))
        self.assertTrue(result['valid'], repr(result))
        self.assertEqual(result['directives'], [
            'ssl_protocols TLSv1.3;',
            'ssl_conf_command Ciphersuites ' + ':'.join(TLS13_SUITES) + ';',
        ])
        self.assertTrue(any('do not apply' in w for w in result['warnings']))


class GroupsTest(ResolveTestCase):
    def test_preset_groups_rendered_with_question_prefixes(self):
        self.assertEqual(self.directives(None)[-1],
                         'ssl_ecdh_curve ?X25519MLKEM768:?X25519:?secp256r1:?secp384r1;')

    def test_omitted_custom_groups_no_directive(self):
        d = self.directives(custom(['ECDHE-RSA-AES128-GCM-SHA256']))
        self.assertFalse([line for line in d if line.startswith('ssl_ecdh_curve')])

    def test_empty_custom_groups_is_no_opinion(self):
        d = self.directives(custom(['ECDHE-RSA-AES128-GCM-SHA256'], []))
        self.assertFalse([line for line in d if line.startswith('ssl_ecdh_curve')])

    def test_explicit_order_preserved(self):
        d = self.directives(custom(['ECDHE-RSA-AES128-GCM-SHA256'], ['secp521r1', 'SecP256r1MLKEM768', 'X25519']))
        self.assertEqual(d[-1], 'ssl_ecdh_curve ?secp521r1:?SecP256r1MLKEM768:?X25519;')

    def test_case_insensitive_rendered_in_openshift_spelling(self):
        d = self.directives(custom(None, ['x25519mlkem768', 'SECP256R1'], 'VersionTLS13'))
        self.assertEqual(d[-1], 'ssl_ecdh_curve ?X25519MLKEM768:?secp256r1;')

    def test_unknown_groups_removed(self):
        # x448 is a real curve but not an OpenShift TLSGroup, so it is dropped;
        # SecP384r1MLKEM1024 is in the enum, so the table-driven resolver keeps it.
        result = self.resolve(custom(['ECDHE-RSA-AES128-GCM-SHA256'], ['x448', 'X25519']))
        self.assertTrue(result['valid'])
        self.assertEqual(result['directives'][-1], 'ssl_ecdh_curve ?X25519;')
        self.assertTrue(any('not an OpenShift TLS group' in w for w in result['warnings']))

    def test_explicit_list_empty_after_filtering_invalid(self):
        self.assertInvalid(custom(None, ['notagroup'], 'VersionTLS13'), 'no usable TLS groups')

    def test_no_question_mark_anywhere_else(self):
        for profile in (None, {'type': 'Modern'}, custom(None, ['X25519'], 'VersionTLS13')):
            for line in self.directives(profile):
                if not line.startswith('ssl_ecdh_curve'):
                    self.assertNotIn('?', line)


class StabilityTest(ResolveTestCase):
    def test_deterministic(self):
        self.assertEqual(self.directives({'type': 'Intermediate'}),
                         self.directives({'type': 'Intermediate', 'intermediate': {}}))

    def test_unrelated_fields_do_not_change_policy(self):
        p1 = custom(['ECDHE-RSA-AES128-GCM-SHA256'], ['X25519'], 'VersionTLS12')
        p2 = custom(['ECDHE-RSA-AES128-GCM-SHA256'], ['X25519'], 'VersionTLS12', unrelated=True)
        self.assertEqual(self.resolve(p1)['directives'], self.resolve(p2)['directives'])


if __name__ == '__main__':
    unittest.main()
