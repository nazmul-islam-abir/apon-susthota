# -*- coding: utf-8 -*-
"""MonoButton uses onPressed, not onTap. Patch the 3 sheet helpers."""
import io, re

path = r'c:\Users\Nazmul\StudioProjects\diabetics_meal-main\lib\screens\workout_screen.dart'

with io.open(path, 'r', encoding='utf-8') as f:
    src = f.read()

# Replace every "onTap: () async {" that comes right after a MonoButton(label:) line.
# The label: line in my code looks like: `                label: '...',`
# The next non-empty line is `                onTap: () async {`.
# We just blanket-replace `onTap: () async {` only inside the new sheet sections,
# but a global scoped replacement is safer here since the rest of the file's
# existing usage is correct (Pressable uses onTap and that's what we want).

# Strategy: only replace inside the bottom-sheet helpers we added.
# Anchor on the line ranges by markers — find the start of _showWaterSheet
# and the end of _showStepsSheet (last "}" before _buildPctChip or similar).
# Easier: just replace ALL occurrences of `MonoButton(` ... `onTap: () async {`
# with `MonoButton(` ... `onPressed: () async {`.

# Use a regex to match "MonoButton(\s*<args>\n\s*label: '...',\n\s*onTap:" pattern.
# We rely on MonoButton's label being immediately followed by onTap in our 3
# insertions. There are exactly 3 such cases in the file now.

pattern = re.compile(
    r"(MonoButton\([^)]*?label:\s*'[^']*',\s*\n\s*)onTap:",
    re.MULTILINE | re.DOTALL,
)

new_src, n = pattern.subn(r"\1onPressed:", src)
print(f'Patched {n} MonoButton.onTap → onPressed')

with io.open(path, 'w', encoding='utf-8') as f:
    f.write(new_src)