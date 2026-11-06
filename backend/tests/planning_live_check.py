"""Live planning check using a temporary confirmed account, always cleaned up.

Only previews are requested. No calendar action is applied and no email is sent.
Credentials stay in memory and are never printed.
"""
import json
from pathlib import Path
import secrets
import subprocess
import tempfile
import uuid

PROJECT = 'fjwdaccejrodpcicyxrc'
BASE = f'https://{PROJECT}.supabase.co'
ROOT = Path(__file__).resolve().parents[2]


def query(sql):
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', encoding='utf-8', delete=False) as file:
        file.write(sql)
        path = file.name
    try:
        result = subprocess.run(['npx.cmd', 'supabase', 'db', 'query', '--linked',
                                 '--project-ref', PROJECT, '--file', path],
                                capture_output=True, text=True, encoding='utf-8', errors='replace')
        if result.returncode:
            raise RuntimeError('Live-check database step failed; no SQL or credentials displayed.')
    finally:
        Path(path).unlink(missing_ok=True)


def request(path, body, headers):
    # Use Windows' verified system certificate store. Secrets travel over stdin,
    # never command-line arguments; TLS certificate validation stays enabled.
    command = r'''
[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$p = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
try {
  $result = Invoke-RestMethod -Uri $p.url -Method Post -Headers $p.headers `
    -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($p.body)) -TimeoutSec 55
  ConvertTo-Json -InputObject $result -Depth 50 -Compress
} catch {
  [Console]::Error.WriteLine('HTTP request failed: ' + [int]$_.Exception.Response.StatusCode)
  exit 1
}
'''
    response = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', command],
        input=json.dumps({'url': BASE + path, 'body': json.dumps(body, ensure_ascii=False), 'headers': headers}),
        capture_output=True, text=True, encoding='utf-8')
    if response.returncode:
        raise RuntimeError(response.stderr.strip())
    return json.loads(response.stdout.lstrip('\ufeff'))


def main():
    import argparse
    import re
    parser = argparse.ArgumentParser()
    parser.add_argument('--scenario', type=int, choices=[1, 2, 3])
    selected = parser.parse_args().scenario
    public_key = re.search(r"anonKey: '([^']+)'", (ROOT / 'lib/main.dart').read_text(encoding='utf-8'))[1]
    owner = str(uuid.uuid4())
    email = f'assistant-check-{owner}@example.invalid'
    password = secrets.token_hex(24)
    courses = ['Cấu trúc dữ liệu và giải thuật', 'Toán rời rạc', 'Lập trình C++']
    created = False
    try:
        subjects = ','.join(f"(gen_random_uuid(),'{owner}','CHECK-{owner}-{i}','{name}','#6750A4')"
                            for i, name in enumerate(courses))
        query(f"""BEGIN;
INSERT INTO auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
  confirmation_token,recovery_token,email_change,email_change_token_new,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES('{owner}','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  '{email}',extensions.crypt('{password}',extensions.gen_salt('bf')),now(),'','','','',
  '{{"provider":"email","providers":["email"]}}','{{"full_name":"AI Planning Check"}}',now(),now());
INSERT INTO public.subjects(id,user_id,subject_code,subject_name,color_code) VALUES {subjects};
COMMIT;""")
        created = True
        session = request('/auth/v1/token?grant_type=password',
                          {'email': email, 'password': password}, {'apikey': public_key})
        headers = {'apikey': public_key, 'Authorization': 'Bearer ' + session['access_token']}
        scenarios = [
            [{'role': 'user', 'content': 'Tôi muốn ôn thi tại nhà ngày 6/11/2026 từ 18:00 đến 24:00. Hãy tự chọn 3 môn trong danh sách môn của tôi và lên lịch giúp tôi, có nghỉ giữa giờ.'}],
            [{'role': 'user', 'content': 'Lên lịch ôn thi tại nhà tối 6/11/2026 từ 18:00 đến 24:00, chia 3 môn.'},
             {'role': 'assistant', 'content': 'Bạn muốn chọn ba môn nào?'},
             {'role': 'user', 'content': 'Bạn tự chọn trong danh sách môn của tôi rồi tạo bản xem trước luôn nhé.'}],
            [{'role': 'user', 'content': 'Tối ngày 6/11/2026 tôi muốn ôn thi 3 môn ở nhà từ 18:00 đến 24:00, hãy lên lịch giúp tôi, có nghỉ giữa giờ.'}],
        ]
        if selected:
            scenarios = [scenarios[selected - 1]]
        reports = []
        for messages in scenarios:
            result = request('/functions/v1/study-assistant',
                             {'messages': messages, 'use_schedule': True, 'allow_actions': True}, headers)
            actions = result.get('actions', [])
            passed = len(actions) == 3 and len({a['title'] for a in actions}) == 3 and all(
                a['title'] in courses and a['date'] == '2026-11-06'
                and a['room'].casefold() == 'tại nhà' and a['end'] < '24:00'
                for a in actions)
            reports.append({'passed': passed, 'actions': actions, 'reply': result.get('reply')})
        report_name = f'planning-live-scenario-{selected}.json' if selected else 'planning-live-check.json'
        (ROOT / 'artifacts' / report_name).write_text(
            json.dumps(reports, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps({'live_checks': len(reports), 'passed': sum(r['passed'] for r in reports)}, ensure_ascii=False))
        if not all(r['passed'] for r in reports):
            raise RuntimeError('Planning behavior needs review; only synthetic replies were saved.')
    finally:
        if created:
            query(f"DELETE FROM auth.users WHERE id='{owner}' AND email='{email}';")
            print('Temporary test account and its data removed.')


if __name__ == '__main__':
    main()
