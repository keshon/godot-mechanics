# -*- coding: utf-8 -*-
"""Собирает README.md из того, что уже есть: таблицы устава, заголовков заметок и
снимков в img/. Отдельный список вести не надо — он разойдётся с первым через неделю.

Запуск:  python tools/readme.py
"""
import io, os, re, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def purpose_rows():
	"""dir -> (механика, эталон, закрыта)"""
	out = {}
	text = io.open(os.path.join(ROOT, 'PURPOSE.md'), encoding='utf-8').read()
	for line in text.split('\n'):
		line = line.strip()
		if not line.startswith('|') or '`' not in line:
			continue
		cells = [c.strip() for c in line.split('|')]
		if len(cells) < 5:
			continue
		name = re.search(r'`([^`]+)`', cells[3])
		if not name:
			continue
		out[name.group(1)] = (cells[1], cells[2], '✓' in cells[3])
	return out


def title_of(notes):
	head = io.open(notes, encoding='utf-8').readline().strip()
	head = head.lstrip('# ').strip()
	return re.sub(r'^(М?\d+|Мультипроба \d+)\s*—\s*', '', head)


def cell(kind, name):
	notes = '%s/%s/NOTES.md' % (kind, name)
	shot = 'img/%s/%s.jpg' % (kind, name)
	title = title_of(os.path.join(ROOT, notes)) if os.path.exists(os.path.join(ROOT, notes)) else ''
	mech, ref, done = purpose_rows().get(name, ('', '—', False))
	tail = [] if ref in ('', '—') else ['эталон: ' + ref]
	if kind == 'probes' and not done:
		tail.append('не закрыта')
	img = '<img src="%s" width="440">' % shot if os.path.exists(os.path.join(ROOT, shot)) else ''
	line = '%s<br><b>%s</b> — %s' % (img, name, title)
	line += '<br><sub><a href="%s/%s/NOTES.md">заметка</a>' % (kind, name)
	if tail:
		line += ' · ' + ' · '.join(tail)
	return line + '</sub>'


def gallery(kind, names, cols=2):
	rows = ['| | |', '|---|---|'] if cols == 2 else ['| |', '|---|']
	for i in range(0, len(names), cols):
		chunk = [cell(kind, n) for n in names[i:i + cols]]
		while len(chunk) < cols:
			chunk.append('')
		rows.append('| ' + ' | '.join(chunk) + ' |')
	return '\n'.join(rows)


def dirs(kind):
	return sorted(os.path.basename(p) for p in glob.glob(os.path.join(ROOT, kind, '*'))
				  if os.path.isdir(p))


HEAD = io.open(os.path.join(ROOT, 'tools', 'readme_head.md'), encoding='utf-8').read()

probes, mixes = dirs('probes'), dirs('mixes')
done = sum(1 for n in probes if purpose_rows().get(n, ('', '', False))[2])

text = HEAD.replace('{PROBES}', str(len(probes))).replace('{DONE}', str(done))
text = text.replace('{MIXES}', str(len(mixes)))
text += '\n## Пробы\n\n' + gallery('probes', probes) + '\n'
text += '\n## Мультипробы\n\n' + gallery('mixes', mixes) + '\n'

io.open(os.path.join(ROOT, 'README.md'), 'w', encoding='utf-8', newline='\n').write(text)
print('README.md: %d проб, %d закрыто, %d мультипроб' % (len(probes), done, len(mixes)))
