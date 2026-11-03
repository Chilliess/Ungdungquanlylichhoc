path = r'c:\Ungdungquanlylichhoc-master\lib\screen\view_schedule_screen.dart'
with open(path, 'rb') as f:
    data = f.read()

# Fix double CR line endings
data = data.replace(b'\r\r\n', b'\n').replace(b'\r\r', b'\r').replace(b'\r\n', b'\n')

# Remove BOM if present
if data.startswith(b'\xef\xbb\xbf'):
    data = data[3:]

with open(path, 'wb') as f:
    f.write(data)

print('Fixed line endings and BOM')