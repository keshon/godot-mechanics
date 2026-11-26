"""Run mechanical checks and short scene startups; never mark a probe accepted."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--render', action='store_true', help='Use the real renderer')
    parser.add_argument('--all', action='store_true', help='Also start every probe and mix')
    parser.add_argument('--output', type=Path,
                        default=Path(tempfile.gettempdir()) / 'godot-mechanics-verification.json')
    args = parser.parse_args()
    base = [args.godot, '--path', str(ROOT)]
    if not args.render:
        base.append('--headless')
    jobs = [('checks', ['--script', 'res://tools/verify.gd']),
            ('bike-checks', ['--script', 'res://tools/verify_bike.gd', '--fixed-fps', '60']),
            ('foundation-checks', ['--script', 'res://tools/verify_foundations.gd',
                                   '--fixed-fps', '60']),
            ('camera-checks', ['--script', 'res://tools/verify_camera.gd', '--fixed-fps', '144']),
            ('motion-checks', ['--script', 'res://tools/verify_motion.gd', '--fixed-fps', '60'])]
    if args.all:
        for kind in ['probes', 'mixes']:
            for folder in sorted((ROOT / kind).iterdir()):
                if not folder.is_dir():
                    continue
                scene = folder / (folder.name.split('_', 1)[1] + '.tscn')
                if not scene.exists():
                    scene = next(iter(sorted(folder.glob('*.tscn'))), None)
                if scene:
                    jobs.append((str(scene.relative_to(ROOT)), [str(scene), '--quit-after', '120']))
    rows = []
    for name, extra in jobs:
        try:
            result = subprocess.run(base + extra, cwd=ROOT, capture_output=True,
                                    encoding='utf-8', errors='replace', timeout=90)
            output = result.stdout + result.stderr
            passed = result.returncode == 0 and 'ERROR:' not in output
            if name in ('checks', 'bike-checks', 'foundation-checks', 'camera-checks', 'motion-checks'):
                passed = passed and 'RESULT checks=' in output and 'failures=0' in output
            rows.append({'name': name, 'passed': passed, 'exit': result.returncode,
                         'output': output})
        except (subprocess.TimeoutExpired, OSError) as error:
            rows.append({'name': name, 'passed': False, 'output': str(error)})
        print(('PASS ' if rows[-1]['passed'] else 'FAIL ') + name, flush=True)
    report = {'utc': datetime.now(timezone.utc).isoformat(), 'render': args.render,
              'startup_frames': 120, 'results': rows}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(args.output)
    return int(any(not row['passed'] for row in rows))


if __name__ == '__main__':
    raise SystemExit(main())
