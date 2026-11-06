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
        """Run the monitor with synthetic search pages; return scanned repos and stderr."""
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
        """Build a search response containing non-fork repositories and its completeness flag."""
        return {'incomplete_results': incomplete,
                'items': [{'name': name, 'fork': False} for name in names]}

    def assert_fallback(self, pages, search_exit=0):
        """Assert failed discovery discards partial results and scans the full registry."""
        scanned, warning = self.run_monitor(pages, search_exit)
        self.assertEqual(scanned, ['fallback-active', 'fallback-ignore', 'fallback-hub'])
        self.assertIn('discovery failed', warning)
        self.assertNotIn('returned no repositories', warning)
        return warning

    def test_complete_pages_keep_all_nonfork_repos(self):
        """Verify complete pages retain unregistered repos, deduplicate names, and exclude forks."""
        first = self.page('unregistered', 'fallback-ignore', 'duplicate')
        first['items'].append({'name': 'forked', 'fork': True})
        scanned, warning = self.run_monitor([first, self.page('duplicate', 'last-page')])
        self.assertEqual(scanned, ['duplicate', 'fallback-ignore', 'last-page', 'unregistered'])
        self.assertEqual(warning, '')

    def test_successful_empty_search(self):
        """Verify empty complete results use the registry with an empty-search warning."""
        scanned, warning = self.run_monitor([self.page()])
        self.assertEqual(len(scanned), 3)
        self.assertIn('returned no repositories', warning)
        self.assertNotIn('discovery failed', warning)

    def test_search_failure(self):
        """Verify a failed search command uses the registry fallback."""
        self.assert_fallback([], search_exit=1)

    def test_failure_after_partial_output(self):
        """Verify a command failure discards repositories already emitted by search."""
        self.assert_fallback([self.page('partial')], search_exit=1)

    def test_nonempty_incomplete_first_page(self):
        """Verify an incomplete first page invalidates otherwise usable search results."""
        warning = self.assert_fallback([self.page('partial', incomplete=True), self.page('later')])
        self.assertIn('response is incomplete', warning)

    def test_nonempty_incomplete_later_page(self):
        """Verify an incomplete later page also discards earlier complete results."""
        self.assert_fallback([self.page('earlier'), self.page('partial', incomplete=True)])

    def test_empty_incomplete_page(self):
        """Verify an empty incomplete page invalidates earlier search results."""
        self.assert_fallback([self.page('earlier'), self.page(incomplete=True)])

    def test_missing_completeness_field(self):
        """Verify responses lacking a completeness flag trigger the registry fallback."""
        self.assert_fallback([{'items': [{'name': 'partial', 'fork': False}]}])


if __name__ == '__main__':
    unittest.main()
