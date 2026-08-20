from pathlib import Path
lines = Path(r"c:\Users\Nazmul\StudioProjects\diabetics_meal-main\lib\screens\dashboard_screen.dart").read_text(encoding='utf-8').splitlines()
print('total =', len(lines))
print('---100..220---')
for i, l in enumerate(lines[99:220], start=100):
    print(f'{i}: {l}')
