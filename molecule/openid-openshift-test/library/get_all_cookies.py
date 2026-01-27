#!/usr/bin/env python3
"""
Custom Ansible module to make HTTP requests and capture ALL Set-Cookie headers.
Ansible's uri module only captures one Set-Cookie header when multiple are present.
"""

import requests
from ansible.module_utils.basic import AnsibleModule

def main():
    module = AnsibleModule(
        argument_spec=dict(
            url=dict(required=True, type='str'),
            validate_certs=dict(required=False, type='bool', default=True),
        )
    )

    url = module.params['url']
    validate_certs = module.params['validate_certs']

    try:
        response = requests.get(url, allow_redirects=False, verify=validate_certs)

        # Extract all Set-Cookie headers (there can be multiple)
        set_cookie_headers = response.headers.get_list('Set-Cookie') if hasattr(response.headers, 'get_list') else []

        # Fallback: if get_list doesn't exist, try to get individual headers
        if not set_cookie_headers:
            set_cookie_headers = [v for k, v in response.raw.headers.items() if k.lower() == 'set-cookie']

        module.exit_json(
            changed=False,
            status=response.status_code,
            location=response.headers.get('Location', ''),
            set_cookie_list=set_cookie_headers,
            set_cookie=set_cookie_headers[-1] if set_cookie_headers else '',
            all_headers=dict(response.headers)
        )
    except Exception as e:
        module.fail_json(msg=str(e))

if __name__ == '__main__':
    main()
