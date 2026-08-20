from pathlib import Path
text = Path(r"c:\Users\Nazmul\StudioProjects\diabetics_meal-main\lib\screens\dashboard_screen.dart").read_text(encoding='utf-8')
import re
for m in re.finditer(r'class _SectionHeader[^{]*\{[^}]{0,200}', text):
    print(m.group(0)[:400])
    print('---')