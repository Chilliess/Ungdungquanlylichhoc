"""Verify Auth returns the deletion hint only for a pending test account.

No emails are sent. A temporary confirmed account is removed in finally.
"""
import json
import re
import secrets
import uuid
from planning_live_check import ROOT, query, request


def main():
    key = re.search(r"anonKey: '([^']+)'", (ROOT / 'lib/main.dart').read_text(encoding='utf-8'))[1]
    owner = str(uuid.uuid4())
    email = f'restore-check-{owner}@example.invalid'
    password = secrets.token_hex(24)
    created = False

    def sign_in():
        return request('/auth/v1/token?grant_type=password', {'email': email, 'password': password}, {'apikey': key})

    try:
        query(f"""INSERT INTO auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
          confirmation_token,recovery_token,email_change,email_change_token_new,
          raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
        VALUES('{owner}','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
          '{email}',extensions.crypt('{password}',extensions.gen_salt('bf')),now(),'','','','',
          '{{"provider":"email","providers":["email"],"keep":"intact"}}',
          '{{"full_name":"Restore Login Check"}}',now(),now());""")
        created = True
        normal = sign_in()
        assert normal['user']['app_metadata'].get('account_deletion_pending') is not True
        headers = {'apikey': key, 'Authorization': 'Bearer ' + normal['access_token']}
        pending = request('/rest/v1/rpc/request_account_deletion', {'p_confirmation': 'delete'}, headers)
        assert pending['status'] == 'pending'
        pending_login = sign_in()
        assert pending_login['user']['app_metadata']['account_deletion_pending'] is True
        assert pending_login['user']['app_metadata']['keep'] == 'intact'
        headers['Authorization'] = 'Bearer ' + pending_login['access_token']
        status = request('/rest/v1/rpc/account_deletion_status', {}, headers)
        assert status['status'] == 'pending'
        restored = request('/rest/v1/rpc/restore_pending_account', {'p_confirm': True}, headers)
        assert restored['status'] == 'active'
        restored_login = sign_in()
        assert restored_login['user']['app_metadata'].get('account_deletion_pending') is not True
        assert restored_login['user']['app_metadata']['keep'] == 'intact'
        print(json.dumps({'normal_login': 'no status hint', 'pending_login': 'restoration required',
                          'restored_login': 'no status hint', 'passed': True}))
    finally:
        if created:
            query(f"DELETE FROM auth.users WHERE id='{owner}' AND email='{email}';")
            print('Temporary test account and its data removed.')


if __name__ == '__main__':
    main()
