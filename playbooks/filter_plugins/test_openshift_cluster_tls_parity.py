import importlib.util
import os
import unittest


def _load_module(module_name, path):
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_ROLE_FILTERS = os.path.join(
    _ROOT, "roles", "default", "ossmconsole-deploy", "filter_plugins", "ossmconsole_nginx_tls.py"
)
_PLAYBOOK_FILTERS = os.path.join(_ROOT, "playbooks", "filter_plugins", "openshift_cluster_tls.py")

_role = _load_module("ossmconsole_nginx_tls", _ROLE_FILTERS)
_playbook = _load_module("openshift_cluster_tls", _PLAYBOOK_FILTERS)

_PROFILE_FIXTURES = [
    {"type": "Modern"},
    {"type": "Intermediate"},
    {"type": "Old"},
    {
        "type": "Custom",
        "custom": {
            "minTLSVersion": "VersionTLS12",
            "ciphers": ["ECDHE-RSA-AES128-GCM-SHA256", "TLS_AES_128_GCM_SHA256"],
            "groups": ["X25519"],
        },
    },
    None,
    {"type": "FutureProfile"},
]

_APISERVER_FIXTURES = [
    {},
    {"tlsAdherence": "LegacyAdheringComponentsOnly", "tlsSecurityProfile": {"type": "Modern"}},
    {"tlsAdherence": "StrictAllComponents", "tlsSecurityProfile": {"type": "Modern"}},
]


class OpenshiftClusterTlsParityTest(unittest.TestCase):
    def test_profile_mapping_matches_role_filters(self):
        for profile in _PROFILE_FIXTURES:
            self.assertEqual(
                _role.ossmconsole_nginx_tls_from_profile(profile),
                _playbook.ossmconsole_nginx_tls_from_profile(profile),
            )

    def test_apiserver_mapping_matches_role_filters(self):
        for spec in _APISERVER_FIXTURES:
            self.assertEqual(
                _role.ossmconsole_nginx_tls_for_apiserver(spec),
                _playbook.ossmconsole_nginx_tls_for_apiserver(spec),
            )

    def test_should_honor_and_fingerprint_match(self):
        policies = ["", None, "LegacyAdheringComponentsOnly", "StrictAllComponents", "FutureUnknownPolicy"]
        for policy in policies:
            self.assertEqual(
                _role.should_honor_cluster_tls_profile(policy),
                _playbook.should_honor_cluster_tls_profile(policy),
            )
        spec = {"tlsAdherence": "StrictAllComponents", "tlsSecurityProfile": {"type": "Intermediate"}}
        self.assertEqual(
            _role.cluster_apiserver_tls_fingerprint(spec),
            _playbook.cluster_apiserver_tls_fingerprint(spec),
        )


if __name__ == "__main__":
    unittest.main()
