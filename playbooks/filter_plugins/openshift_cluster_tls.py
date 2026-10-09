from __future__ import absolute_import, division, print_function

import json

__metaclass__ = type

# Keep in sync with roles/default|v2.27|v2.33/ossmconsole-deploy/filter_plugins/ossmconsole_nginx_tls.py

_BUILTIN_PROFILES = {
    "Old": {
        "minTLSVersion": "VersionTLS10",
        "ciphers": [
            "TLS_AES_128_GCM_SHA256",
            "TLS_AES_256_GCM_SHA384",
            "TLS_CHACHA20_POLY1305_SHA256",
            "ECDHE-ECDSA-AES128-GCM-SHA256",
            "ECDHE-RSA-AES128-GCM-SHA256",
            "ECDHE-ECDSA-AES256-GCM-SHA384",
            "ECDHE-RSA-AES256-GCM-SHA384",
            "ECDHE-ECDSA-CHACHA20-POLY1305",
            "ECDHE-RSA-CHACHA20-POLY1305",
            "ECDHE-ECDSA-AES128-SHA256",
            "ECDHE-RSA-AES128-SHA256",
            "ECDHE-ECDSA-AES128-SHA",
            "ECDHE-RSA-AES128-SHA",
            "ECDHE-ECDSA-AES256-SHA384",
            "ECDHE-RSA-AES256-SHA384",
            "ECDHE-ECDSA-AES256-SHA",
            "ECDHE-RSA-AES256-SHA",
            "AES128-GCM-SHA256",
            "AES256-GCM-SHA384",
            "AES128-SHA256",
            "AES256-SHA256",
            "AES128-SHA",
            "AES256-SHA",
            "DES-CBC3-SHA",
        ],
        "groups": ["X25519MLKEM768", "X25519", "secp256r1", "secp384r1"],
    },
    "Intermediate": {
        "minTLSVersion": "VersionTLS12",
        "ciphers": [
            "TLS_AES_128_GCM_SHA256",
            "TLS_AES_256_GCM_SHA384",
            "TLS_CHACHA20_POLY1305_SHA256",
            "ECDHE-ECDSA-AES128-GCM-SHA256",
            "ECDHE-RSA-AES128-GCM-SHA256",
            "ECDHE-ECDSA-AES256-GCM-SHA384",
            "ECDHE-RSA-AES256-GCM-SHA384",
            "ECDHE-ECDSA-CHACHA20-POLY1305",
            "ECDHE-RSA-CHACHA20-POLY1305",
        ],
        "groups": ["X25519MLKEM768", "X25519", "secp256r1", "secp384r1"],
    },
    "Modern": {
        "minTLSVersion": "VersionTLS13",
        "ciphers": [
            "TLS_AES_128_GCM_SHA256",
            "TLS_AES_256_GCM_SHA384",
            "TLS_CHACHA20_POLY1305_SHA256",
        ],
        "groups": ["X25519MLKEM768", "X25519", "secp256r1", "secp384r1"],
    },
}

_DEFAULT_GROUPS = _BUILTIN_PROFILES["Intermediate"]["groups"]

_OPTIONAL_NGINX_CURVES = frozenset(
    {"X25519MLKEM768", "SecP256r1MLKEM768", "SecP384r1MLKEM1024"}
)

_MIN_VERSION_PROTOCOLS = {
    "VersionTLS10": "TLSv1 TLSv1.1 TLSv1.2 TLSv1.3",
    "VersionTLS11": "TLSv1.1 TLSv1.2 TLSv1.3",
    "VersionTLS12": "TLSv1.2 TLSv1.3",
    "VersionTLS13": "TLSv1.3",
}

_LEGACY_NGINX_TLS = {
    "ssl_protocols": "TLSv1.3",
    "ssl_ciphers": "",
    "ssl_ciphersuites_line": "",
    "ssl_ecdh_curve": "?X25519MLKEM768:?SecP256r1MLKEM768:?X25519:secp256r1:secp384r1",
}


def should_honor_cluster_tls_profile(adherence_policy):
    if adherence_policy is None:
        return False
    policy = str(adherence_policy).strip()
    if policy == "":
        return False
    if policy == "LegacyAdheringComponentsOnly":
        return False
    if policy == "StrictAllComponents":
        return True
    return True


def _resolve_profile_spec(profile):
    if not profile:
        return dict(_BUILTIN_PROFILES["Intermediate"])

    profile_type = profile.get("type") or "Intermediate"
    if profile_type in _BUILTIN_PROFILES:
        return dict(_BUILTIN_PROFILES[profile_type])

    if profile_type == "Custom":
        custom = profile.get("custom") or {}
        return {
            "minTLSVersion": custom.get("minTLSVersion") or "VersionTLS12",
            "ciphers": list(custom.get("ciphers") or []),
            "groups": list(custom.get("groups") or _DEFAULT_GROUPS),
        }

    return dict(_BUILTIN_PROFILES["Intermediate"])


def _is_tls13_cipher(name):
    return name.startswith("TLS_AES_") or name.startswith("TLS_CHACHA20_POLY1305_")


def _nginx_curve_name(group):
    name = str(group).strip()
    if name in _OPTIONAL_NGINX_CURVES:
        return "?{0}".format(name)
    return name


def cluster_apiserver_tls_fingerprint(apiserver_spec):
    if apiserver_spec is None:
        apiserver_spec = {}
    payload = {
        "tlsAdherence": apiserver_spec.get("tlsAdherence") or "",
        "tlsSecurityProfile": apiserver_spec.get("tlsSecurityProfile") or {},
    }
    return json.dumps(payload, sort_keys=True, separators=(",", ":"))


def ossmconsole_nginx_tls_for_apiserver(apiserver_spec):
    if apiserver_spec is None:
        apiserver_spec = {}
    adherence = apiserver_spec.get("tlsAdherence")
    if not should_honor_cluster_tls_profile(adherence):
        return dict(_LEGACY_NGINX_TLS)
    return ossmconsole_nginx_tls_from_profile(apiserver_spec.get("tlsSecurityProfile"))


def ossmconsole_nginx_tls_from_profile(profile):
    spec = _resolve_profile_spec(profile)
    min_version = spec.get("minTLSVersion") or "VersionTLS12"
    ssl_protocols = _MIN_VERSION_PROTOCOLS.get(min_version, "TLSv1.2 TLSv1.3")

    ciphers = spec.get("ciphers") or []
    tls13 = [c for c in ciphers if _is_tls13_cipher(c)]
    tls12 = [c for c in ciphers if c not in tls13]

    ssl_ciphers = ""
    if tls12 and min_version != "VersionTLS13":
        ssl_ciphers = ":".join(tls12)

    ssl_ciphersuites_line = ""
    if tls13:
        ssl_ciphersuites_line = "ssl_conf_command Ciphersuites {0};".format(":".join(tls13))

    groups = spec.get("groups") or _DEFAULT_GROUPS
    ssl_ecdh_curve = ":".join(_nginx_curve_name(g) for g in groups)

    return {
        "ssl_protocols": ssl_protocols,
        "ssl_ciphers": ssl_ciphers,
        "ssl_ciphersuites_line": ssl_ciphersuites_line,
        "ssl_ecdh_curve": ssl_ecdh_curve,
    }


class FilterModule(object):
    def filters(self):
        return {
            "cluster_apiserver_tls_fingerprint": cluster_apiserver_tls_fingerprint,
            "ossmconsole_nginx_tls_from_profile": ossmconsole_nginx_tls_from_profile,
            "ossmconsole_nginx_tls_for_apiserver": ossmconsole_nginx_tls_for_apiserver,
            "should_honor_cluster_tls_profile": should_honor_cluster_tls_profile,
        }
