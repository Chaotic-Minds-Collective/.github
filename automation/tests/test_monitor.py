"""Exercise monitor discovery with synthetic GitHub responses and no network."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'scripts' / 'monitor.sh'


class DiscoveryTests(unittest.TestCase):
    def run_monitor(self, pages, search_exit=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'automation').mkdir()
            (root / 'automation/repos.txt').write_text('fallback-active active\nfallback-ignore ignore\nfallback-hub hub\n')
            gh = root / 'gh'
            gh.write_text(f'#!{sys.executable}\n' + '''import json, os, sys
from pathlib import Path
args = sys.argv[1:]
if any(arg.startswith('search/repositories?') for arg in args):
    assert '--paginate' in args
    assert 'fork:false' in args[args.index('--paginate') + 1]
    for page in json.loads(os.environ['SEARCH_PAGES']):
        print(json.dumps(page))
    sys.exit(int(os.environ['SEARCH_EXIT']))
with Path('scanned').open('a') as log:
    log.write(args[1].split('/')[2] + '\\n')
print('{"workflow_runs": []}')
''')
            gh.chmod(0o755)
            env = dict(os.environ, PATH=f'{root}:{os.environ["PATH"]}',
                       DISCORD_WEBHOOK_URL='https://invalid.example.test',
                       SEARCH_PAGES=json.dumps(pages), SEARCH_EXIT=str(search_exit))
            # Sandbox shell initialization may prepend a real gh wrapper to PATH.
            env.pop('BASH_ENV', None)
            result = subprocess.run(['bash', str(SCRIPT)], cwd=root, env=env,
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            scanned = (root / 'scanned').read_text().splitlines()
            return scanned, result.stderr

    def page(self, *names, incomplete=False):
        return {'incomplete_results': incomplete,
                'items': [{'name': name, 'fork': False} for name in names]}

    def assert_fallback(self, pages, search_exit=0):
        scanned, warning = self.run_monitor(pages, search_exit)
        self.assertEqual(scanned, ['fallback-active', 'fallback-ignore', 'fallback-hub'])
        self.assertIn('discovery failed', warning)
        self.assertNotIn('returned no repositories', warning)
        return warning

    def test_complete_pages_keep_all_nonfork_repos(self):
        first = self.page('unregistered', 'fallback-ignore', 'duplicate')
        first['items'].append({'name': 'forked', 'fork': True})
        scanned, warning = self.run_monitor([first, self.page('duplicate', 'last-page')])
        self.assertEqual(scanned, ['duplicate', 'fallback-ignore', 'last-page', 'unregistered'])
        self.assertEqual(warning, '')

    def test_successful_empty_search(self):
        scanned, warning = self.run_monitor([self.page()])
        self.assertEqual(len(scanned), 3)
        self.assertIn('returned no repositories', warning)
        self.assertNotIn('discovery failed', warning)

    def test_search_failure(self):
        self.assert_fallback([], search_exit=1)

    def test_failure_after_partial_output(self):
        self.assert_fallback([self.page('partial')], search_exit=1)

    def test_nonempty_incomplete_first_page(self):
        warning = self.assert_fallback([self.page('partial', incomplete=True), self.page('later')])
        self.assertIn('response is incomplete', warning)

    def test_nonempty_incomplete_later_page(self):
        self.assert_fallback([self.page('earlier'), self.page('partial', incomplete=True)])

    def test_empty_incomplete_page(self):
        self.assert_fallback([self.page('earlier'), self.page(incomplete=True)])

    def test_missing_completeness_field(self):
        self.assert_fallback([{'items': [{'name': 'partial', 'fork': False}]}])


if __name__ == '__main__':
    unittest.main()
