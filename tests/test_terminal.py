"""Real Gum terminal flows; optional pexpect is only a development dependency."""
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from test_project import ROOT, FAKE_CODEX, FAKE_CURL

HAS_PEXPECT = importlib.util.find_spec('pexpect') is not None
if HAS_PEXPECT:
    import pexpect

@unittest.skipUnless(HAS_PEXPECT, 'Install pexpect to run real terminal tests')
class TerminalTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='fantasy terminal ')
        self.directory = Path(self.temp.name)
        binaries = self.directory/'bin'
        binaries.mkdir()
        for name, content in [('codex',FAKE_CODEX),('curl',FAKE_CURL)]:
            file=binaries/name
            file.write_text(content)
            file.chmod(0o755)
        self.env=dict(os.environ, BOOK_DB=str(self.directory/'real.csv'),
                      FAKE_LOG=str(self.directory/'events'),
                      PATH=str(binaries)+os.pathsep+os.environ['PATH'], TERM='xterm-256color')
        self.child=None
    def tearDown(self):
        if self.child is not None and self.child.isalive():
            self.child.close(force=True)
        self.temp.cleanup()
    def start(self, demo=False):
        self.child=pexpect.spawn('/bin/bash',[str(ROOT/'app.sh')]+(['--demo'] if demo else []),
                                 env=self.env,encoding='utf-8',timeout=12,dimensions=(35,110))
    def expect(self, text):
        self.child.expect(re.escape(text))
    def choose(self, heading, index=0):
        self.expect(heading)
        self.child.send('\x1b[B'*index+'\r')
    def entry(self, heading, value=None):
        self.expect(heading)
        if value is not None:
            self.child.send('\x05\x15'+value)
        self.child.send('\r')
    def pause(self):
        self.entry('Press Enter to return')
    def rows(self):
        result=subprocess.run(['bash',str(ROOT/'data/book_database.sh'),'list'],env=self.env,capture_output=True,text=True,check=True)
        return [json.loads(line) for line in result.stdout.splitlines()]
    def finish(self):
        self.choose('Where next?',5)
        self.child.expect(pexpect.EOF)
        self.child.close()
        self.assertEqual(self.child.exitstatus,0)
    def test_library_flow(self):
        self.start()
        self.choose('Where next?')
        self.expect('No books found.')
        self.pause()
        self.choose('Where next?',1)
        self.entry('Book title','The Hobbit')
        self.entry('Author (optional for lookup)','J. R. R. Tolkien')
        self.choose('How would you like to add it?',1)
        self.entry('Title (required)')
        self.entry('Author (required)')
        self.entry('Genre (optional)','Fantasy')
        self.entry('Book information URL (optional)')
        self.choose('Reading status')
        self.choose('Rating')
        self.expect('Save this book?')
        self.child.send('y\r')
        self.expect('Saved: The Hobbit')
        self.pause()
        self.choose('Where next?',2)
        self.entry('Search title, author, or genre','hobbit')
        self.choose('Choose a book')
        self.expect('Status: want-to-read')
        self.pause()
        self.choose('Where next?',3)
        self.choose('Choose a book')
        self.choose('Reading status',2)
        self.choose('Rating',5)
        self.expect('Reading progress updated.')
        self.pause()
        # Esc cancels Add without losing the existing record.
        self.choose('Where next?',1)
        self.expect('Book title')
        self.child.send('\x1b')
        self.finish()
        self.assertEqual(self.rows()[0]['status'],'finished')
        self.assertEqual(self.rows()[0]['rating'],'5')
    def test_demo_recommendations_and_cache(self):
        self.start(demo=True)
        self.expect('DEMO: temporary sample library')
        self.choose('Where next?',4)
        self.choose('AI recommendations use your Codex allowance')
        self.entry('Any interests today?','Dragons')
        self.choose('Choose a book')
        self.expect('Why: A new adventure')
        self.choose('Next step')
        # Empty fake metadata falls back to editable recommendation fields.
        self.entry('Title (required)')
        self.entry('Author (required)')
        self.entry('Genre (optional)')
        self.entry('Book information URL (optional)')
        self.choose('Reading status')
        self.choose('Rating')
        self.expect('Save this book?')
        self.child.send('y\r')
        self.expect('Saved: history0')
        self.pause()
        self.choose('Your recommendations')
        self.choose('Choose a book')
        self.choose('Next step',1)
        self.choose('Your recommendations',2)
        self.choose('Where next?')
        self.expect('4. history0')
        self.child.send('\x1b')
        self.pause()
        self.finish()
        self.assertEqual(self.rows(),[], 'Demo must not touch the real library')
        events=[json.loads(line) for line in Path(self.env['FAKE_LOG']).read_text().splitlines()]
        self.assertEqual(sum(e['event']=='start' for e in events),3,'Cached browsing must not rerun AI')
