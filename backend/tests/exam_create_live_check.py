"""Exercise the same RPC as the exam editor; remove the temporary account."""
import re
import secrets
import uuid
from planning_live_check import ROOT, query, request


def main():
    key = re.search(r"anonKey: '([^']+)'", (ROOT / 'lib/main.dart').read_text(encoding='utf-8'))[1]
    owner = str(uuid.uuid4())
    email, password = f'exam-check-{owner}@example.invalid', secrets.token_hex(24)
    created = False
    try:
        query(f"""INSERT INTO auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
          confirmation_token,recovery_token,email_change,email_change_token_new,
          raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
        VALUES('{owner}','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
          '{email}',extensions.crypt('{password}',extensions.gen_salt('bf')),now(),'','','','',
          '{{"provider":"email","providers":["email"]}}','{{"full_name":"Exam Save Check"}}',now(),now());""")
        created = True
        auth = request('/auth/v1/token?grant_type=password', {'email': email, 'password': password}, {'apikey': key})
        headers = {'apikey': key, 'Authorization': 'Bearer ' + auth['access_token']}
        params = {'p_title': 'Toán', 'p_date': '2026-11-08', 'p_start': '19:00', 'p_end': '20:00',
                  'p_room': 'A1, 101', 'p_notes': 'Synthetic exam test', 'p_category': 'Thực hành',
                  'p_id': None, 'p_is_exam': True, 'p_occurrence_date': '2026-11-08'}
        exam = request('/rest/v1/rpc/save_calendar_lesson', params, headers)
        uuid.UUID(exam)
        params.update(p_id=exam, p_start='18:00', p_end='19:00')
        assert request('/rest/v1/rpc/save_calendar_lesson', params, headers) == exam
        print('Live exam editor API: create and edit passed.')
    finally:
        if created:
            query(f"DELETE FROM auth.users WHERE id='{owner}' AND email='{email}';")
            print('Temporary account, exam and subject removed.')


if __name__ == '__main__':
    main()
