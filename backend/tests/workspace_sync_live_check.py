"""Two independent Auth sessions; only a generated temporary account is used."""
import json
import re
import secrets
import uuid
from planning_live_check import ROOT, query, request


def main():
    key = re.search(r"anonKey: '([^']+)'", (ROOT / 'lib/main.dart').read_text(encoding='utf-8'))[1]
    owner, subject = str(uuid.uuid4()), str(uuid.uuid4())
    email, password = f'workspace-check-{owner}@example.invalid', secrets.token_hex(24)
    created = False
    try:
        query(f"""BEGIN;
        INSERT INTO auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
          confirmation_token,recovery_token,email_change,email_change_token_new,
          raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
        VALUES('{owner}','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
          '{email}',extensions.crypt('{password}',extensions.gen_salt('bf')),now(),'','','','',
          '{{"provider":"email","providers":["email"]}}','{{"full_name":"Workspace Check"}}',now(),now());
        INSERT INTO public.subjects(id,user_id,subject_name,subject_code) VALUES('{subject}','{owner}','Sync Subject','SYNC');
        COMMIT;""")
        created = True
        def login():
            auth = request('/auth/v1/token?grant_type=password', {'email': email, 'password': password}, {'apikey': key})
            return {'apikey': key, 'Authorization': 'Bearer ' + auth['access_token']}
        a, b = login(), login()
        def sync(headers, collection, changes=None):
            return request('/rest/v1/rpc/sync_workspace_items', {'p_collection': collection, 'p_changes': changes or []}, headers)
        def change(id, title, **extra):
            return {'id': id, 'payload': {'id': id, 'title': title, **extra}, 'overwrite': True}
        sync(a, 'tasks', [change('a', 'From device A', subjectId=subject)])
        assert sync(b, 'tasks')[0]['payload']['subjectId'] == subject
        assert len(sync(b, 'tasks', [change('b', 'From device B')])) == 2
        assert len(sync(a, 'tasks', [change('a', 'Edited on A', subjectId=subject)])) == 2
        sync(b, 'tasks', [{'id': 'a', 'deleted': True, 'overwrite': True}])
        legacy = change('a', 'Old local backup', subjectId=subject)
        legacy['overwrite'] = False
        assert next(r for r in sync(a, 'tasks', [legacy]) if r['id'] == 'a')['deleted'] is True
        sync(a, 'chat', [change('thread', 'Chat sync', messages=[{'role': 'user', 'content': 'Synthetic check'}])])
        assert sync(b, 'chat')[0]['payload']['messages'][0]['content'] == 'Synthetic check'
        sync(b, 'chat', [{'id': 'thread', 'deleted': True, 'overwrite': True}])
        assert sync(a, 'chat')[0]['deleted'] is True
        print(json.dumps({'two_sessions': True, 'task_merge': True, 'subject_link': True,
                          'deletion_no_resurrection': True, 'chat_sync_and_delete': True, 'passed': True}))
    finally:
        if created:
            query(f"DELETE FROM auth.users WHERE id='{owner}' AND email='{email}';")
            print('Temporary account, subject and workspace rows removed.')


if __name__ == '__main__':
    main()
