import unittest

from ossmconsole_nginx_tls import (
    cluster_apiserver_tls_fingerprint,
    ossmconsole_nginx_tls_for_apiserver,
    ossmconsole_nginx_tls_from_profile,
    should_honor_cluster_tls_profile,
)


class OssmconsoleNginxTlsTest(unittest.TestCase):
    def test_modern_profile_excludes_ccm_and_uses_tls13_only(self):
        result = ossmconsole_nginx_tls_from_profile({"type": "Modern"})
        self.assertEqual(result["ssl_protocols"], "TLSv1.3")
        self.assertIn("TLS_AES_128_GCM_SHA256", result["ssl_ciphersuites_line"])
        self.assertIn("TLS_CHACHA20_POLY1305_SHA256", result["ssl_ciphersuites_line"])
        self.assertNotIn("CCM", result["ssl_ciphersuites_line"])
        self.assertEqual(result["ssl_ciphers"], "")

    def test_intermediate_profile_includes_tls12_ciphers(self):
        result = ossmconsole_nginx_tls_from_profile({"type": "Intermediate"})
        self.assertEqual(result["ssl_protocols"], "TLSv1.2 TLSv1.3")
        self.assertIn("ECDHE-RSA-AES128-GCM-SHA256", result["ssl_ciphers"])
        self.assertIn("ssl_conf_command Ciphersuites", result["ssl_ciphersuites_line"])

    def test_old_profile_includes_legacy_ciphers_and_tls13_suites(self):
        result = ossmconsole_nginx_tls_from_profile({"type": "Old"})
        self.assertEqual(result["ssl_protocols"], "TLSv1 TLSv1.1 TLSv1.2 TLSv1.3")
        self.assertIn("DES-CBC3-SHA", result["ssl_ciphers"])
        self.assertIn("TLS_AES_128_GCM_SHA256", result["ssl_ciphersuites_line"])

    def test_custom_profile(self):
        result = ossmconsole_nginx_tls_from_profile(
            {
                "type": "Custom",
                "custom": {
                    "minTLSVersion": "VersionTLS13",
                    "ciphers": ["TLS_AES_128_GCM_SHA256"],
                    "groups": ["X25519MLKEM768"],
                },
            }
        )
        self.assertEqual(result["ssl_protocols"], "TLSv1.3")
        self.assertIn("?X25519MLKEM768", result["ssl_ecdh_curve"])
        self.assertIn("TLS_AES_128_GCM_SHA256", result["ssl_ciphersuites_line"])

    def test_missing_profile_defaults_to_intermediate(self):
        result = ossmconsole_nginx_tls_from_profile(None)
        self.assertEqual(result["ssl_protocols"], "TLSv1.2 TLSv1.3")

    def test_unknown_profile_type_defaults_to_intermediate(self):
        result = ossmconsole_nginx_tls_from_profile({"type": "FutureProfile"})
        self.assertEqual(result["ssl_protocols"], "TLSv1.2 TLSv1.3")

    def test_should_honor_strict_only(self):
        self.assertFalse(should_honor_cluster_tls_profile(""))
        self.assertFalse(should_honor_cluster_tls_profile(None))
        self.assertFalse(should_honor_cluster_tls_profile("LegacyAdheringComponentsOnly"))
        self.assertTrue(should_honor_cluster_tls_profile("StrictAllComponents"))
        self.assertTrue(should_honor_cluster_tls_profile("FutureUnknownPolicy"))

    def test_legacy_adherence_uses_legacy_nginx_tls(self):
        result = ossmconsole_nginx_tls_for_apiserver(
            {"tlsAdherence": "LegacyAdheringComponentsOnly", "tlsSecurityProfile": {"type": "Modern"}}
        )
        self.assertEqual(result["ssl_protocols"], "TLSv1.3")
        self.assertEqual(result["ssl_ciphersuites_line"], "")

    def test_strict_adherence_uses_modern_profile(self):
        result = ossmconsole_nginx_tls_for_apiserver(
            {"tlsAdherence": "StrictAllComponents", "tlsSecurityProfile": {"type": "Modern"}}
        )
        self.assertEqual(result["ssl_protocols"], "TLSv1.3")
        self.assertIn("TLS_AES_128_GCM_SHA256", result["ssl_ciphersuites_line"])

    def test_empty_apiserver_spec_uses_legacy_nginx_tls(self):
        for spec in ({}, None):
            result = ossmconsole_nginx_tls_for_apiserver(spec)
            self.assertEqual(result["ssl_protocols"], "TLSv1.3")
            self.assertEqual(result["ssl_ciphersuites_line"], "")

    def test_strict_adherence_without_profile_defaults_intermediate(self):
        result = ossmconsole_nginx_tls_for_apiserver({"tlsAdherence": "StrictAllComponents"})
        self.assertEqual(result["ssl_protocols"], "TLSv1.2 TLSv1.3")

    def test_cluster_apiserver_tls_fingerprint_is_stable(self):
        spec = {"tlsAdherence": "StrictAllComponents", "tlsSecurityProfile": {"type": "Modern"}}
        self.assertEqual(
            cluster_apiserver_tls_fingerprint(spec),
            cluster_apiserver_tls_fingerprint(spec),
        )


if __name__ == "__main__":
    unittest.main()
