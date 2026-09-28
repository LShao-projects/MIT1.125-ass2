"""Isolated integration tests. Fakes exercise processes without spending AI allowance."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]

FAKE_CODEX = r'''#!/usr/bin/env python3
import json, os, sys, time, subprocess
from pathlib import Path
if sys.argv[1:3] == ['login', 'status']:
    print(os.environ.get('FAKE_AUTH', 'Logged in using ChatGPT'))
    sys.exit(0)
schema = json.loads(Path(sys.argv[sys.argv.index('--output-schema')+1]).read_text())
assert schema['properties']['books']['items']['required'] == ['title','author','genre','reason']
prompt = sys.stdin.read()
strategy = next(s for s in ['history','interests','discovery'] if 'Strategy: ' + s + '.' in prompt)
if os.environ.get('FAKE_PROMPTS'):
    (Path(os.environ['FAKE_PROMPTS']) / (strategy + '.txt')).write_text(prompt)
log = Path(os.environ['FAKE_LOG'])
with log.open('a') as f:
    f.write(json.dumps({'strategy':strategy,'event':'start','time':time.time(),'pid':os.getpid()})+'\n')
mode = os.environ.get('FAKE_MODE', 'ok')
if mode == 'hang':
    child = subprocess.Popen(['sleep','30'])
    with log.open('a') as f:
        f.write(json.dumps({'event':'child','pid':child.pid})+'\n')
    time.sleep(30)
time.sleep(.3)
if mode == 'fail' or (mode == 'partial' and strategy == 'history'):
    print('ERROR: Simulated service unavailable', file=sys.stderr)
    sys.exit(1)
output = sys.argv[sys.argv.index('--output-last-message')+1]
books = [{'title':strategy + str(i), 'author':'Writer', 'genre':'Fantasy', 'reason':'A new adventure'} for i in range(3)]
Path(output).write_text('bad json' if mode == 'malformed' else json.dumps({'books':books}))
with log.open('a') as f:
    f.write(json.dumps({'strategy':strategy,'event':'end','time':time.time()})+'\n')
'''
FAKE_CURL = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
if os.environ.get('FAKE_CURL_LOG'):
    Path(os.environ['FAKE_CURL_LOG']).write_text(json.dumps(sys.argv[1:]))
# Reproduce Open Library's server error for an empty author filter.
if any(arg.startswith('author=') and not arg.split('=', 1)[1].strip() for arg in sys.argv[1:]):
    print('curl: (22) The requested URL returned error: 500', file=sys.stderr)
    sys.exit(22)
sys.stdout.write(os.environ.get('FAKE_METADATA','{"docs":[]}'))
sys.exit(int(os.environ.get('FAKE_CURL_STATUS','0')))
'''

def book(title='The Hobbit', author='J. R. R. Tolkien', **extra):
    return dict(title=title, author=author, genre='Fantasy', status='want-to-read', rating='', link='', **extra)

class ProjectTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='book tests ')
        self.directory = Path(self.temp.name)
        self.bin = self.directory / 'bin'
        self.bin.mkdir()
        for name, source in [('codex',FAKE_CODEX),('curl',FAKE_CURL)]:
            path = self.bin / name
            path.write_text(source)
            path.chmod(0o755)
        self.env = dict(os.environ, BOOK_DB=str(self.directory/'library.csv'),
                        FAKE_LOG=str(self.directory/'events'),
                        PATH=str(self.bin)+os.pathsep+os.environ['PATH'])
    def tearDown(self):
        self.temp.cleanup()
    def run_script(self, path, *args, input='', check=True):
        result = subprocess.run(['/bin/bash',str(ROOT/path),*args], input=input, text=True,
                                capture_output=True, env=self.env, timeout=15)
        if check:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result
    def db(self, command, *args, value=None, check=True):
        return self.run_script('data/book_database.sh',command,*args,
                               input=json.dumps(value) if value is not None else '', check=check)
    def records(self, output):
        return [json.loads(line) for line in output.splitlines()]
    def test_storage_and_search(self):
        self.assertEqual(self.db('list').stdout,'')
        record = book('The "Dragon, Mage" — 魔法')
        self.db('add',value=record)
        self.assertEqual(self.records(self.db('list').stdout),[record])
        self.assertEqual(len(self.records(self.db('search','DRAGON').stdout)),1)
        self.assertEqual(len(self.records(self.run_script('books/search_books.sh',input='fantasy\n').stdout)),1)
        self.db('update',record['title'],record['author'],value={'status':'finished','rating':'5'})
        self.assertEqual(self.records(self.db('list').stdout)[0]['rating'],'5')
        self.db('exists',record['title'].upper(),record['author'])
        self.assertEqual(self.db('exists','missing','writer',check=False).returncode,1)
    def test_invalid_and_duplicate_leave_storage_unchanged(self):
        record=book()
        self.db('add',value=record)
        before=self.db('list').stdout
        for invalid in [dict(record,title='  THE   HOBBIT '),dict(record,title=''),dict(record,rating='6'),dict(record,status='bad'),dict(record,title='new\nline'),dict(record,link='javascript:bad')]:
            self.assertEqual(self.db('add',value=invalid,check=False).returncode,2)
            self.assertEqual(self.db('list').stdout,before)
        self.assertEqual(self.db('update','missing','writer',value={'rating':'3'},check=False).returncode,2)
    def test_metadata(self):
        self.env['FAKE_METADATA']=json.dumps({'docs':[{'title':'The Hobbit','author_name':['Tolkien'],'key':'/works/OL1W','subject':['Fantasy']},{'title':'Unknown'}]})
        found=self.records(self.run_script('books/fetch_book_metadata.sh','Hobbit').stdout)
        self.assertEqual(len(found),2)
        self.assertEqual(found[0]['link'],'https://openlibrary.org/works/OL1W')
        self.assertEqual(found[1]['author'],'')
        self.env['FAKE_METADATA']='{"docs":[]}'
        self.assertEqual(self.run_script('books/fetch_book_metadata.sh','missing').stdout,'')
        self.env['FAKE_METADATA']='not json'
        self.assertNotEqual(self.run_script('books/fetch_book_metadata.sh','bad',check=False).returncode,0)
        self.env['FAKE_CURL_STATUS']='22'
        self.assertNotEqual(self.run_script('books/fetch_book_metadata.sh','bad',check=False).returncode,0)
    def test_metadata_optional_author(self):
        log=self.directory/'curl-arguments.json'
        self.env['FAKE_CURL_LOG']=str(log)
        self.env['FAKE_METADATA']=json.dumps({'docs':[{'title':'The Hobbit','author_name':['Tolkien']}]})
        for args in [('The Hobbit',), ('The Hobbit',''), ('The Hobbit',' \t ')]:
            with self.subTest(args=args):
                result=self.run_script('books/fetch_book_metadata.sh',*args)
                self.assertEqual(self.records(result.stdout)[0]['title'],'The Hobbit')
                request=json.loads(log.read_text())
                self.assertIn('title=The Hobbit',request)
                self.assertFalse(any(arg.startswith('author=') for arg in request))
        self.run_script('books/fetch_book_metadata.sh','The Hobbit','J. R. R. Tolkien')
        request=json.loads(log.read_text())
        self.assertIn('author=J. R. R. Tolkien',request)
        self.assertEqual(request[request.index('author=J. R. R. Tolkien')-1],'--data-urlencode')
    def test_refinement(self):
        self.db('add',value=book('Owned','Writer'))
        candidates=[]
        for strategy in ['history','interests','discovery']:
            for title in ['Owned','Shared',strategy+'1',strategy+'2']:
                candidates.append(dict(title=title,author='Writer',genre='Fantasy',reason='Why',strategy=strategy))
        result=self.run_script('recommendations/refine_recommendations.sh',input='bad\n'+ '\n'.join(map(json.dumps,candidates)))
        records=self.records(result.stdout)
        self.assertEqual(len(records),5)
        self.assertEqual([r['strategy'] for r in records[:3]],['history','interests','discovery'])
        self.assertNotIn('Owned',[r['title'] for r in records])
        self.assertEqual(len(set(r['title'] for r in records)),5)
        self.assertIn('Skipped malformed',result.stderr)
    def test_refinement_polishes_display_fields(self):
        candidates = [dict(title='  The   Last Unicorn  ', author=' Peter S.  Beagle ',
                           genre='  Mythic   Fantasy ', reason=' Hope   amid  loss. ',
                           strategy='history'),
                      dict(title='the last unicorn', author='peter s. beagle',
                           genre='Fantasy', reason='Duplicate', strategy='interests')]
        result = self.run_script('recommendations/refine_recommendations.sh',
                                 input='\n'.join(map(json.dumps, candidates)))
        self.assertEqual(self.records(result.stdout), [dict(
            title='The Last Unicorn', author='Peter S. Beagle', genre='Mythic Fantasy',
            reason='Hope amid loss.', strategy='history')])

    def test_parallel_success_and_partial_failure(self):
        result=self.run_script('workflows/get_recommendations.sh')
        self.assertEqual(len(self.records(result.stdout)),5)
        self.assertIn('running',result.stderr)
        self.assertIn('done',result.stderr)
        events=self.records(Path(self.env['FAKE_LOG']).read_text())
        starts=[e['time'] for e in events if e['event']=='start']
        ends=[e['time'] for e in events if e['event']=='end']
        self.assertEqual(len(starts),3)
        self.assertLess(max(starts),min(ends),'All three calls must overlap')
        self.env['FAKE_MODE']='partial'
        result=self.run_script('workflows/get_recommendations.sh')
        self.assertEqual(len(self.records(result.stdout)),5)
        self.assertIn('failed',result.stderr)
        self.assertTrue(all(r['strategy']!='history' for r in self.records(result.stdout)))
    def test_standalone_recommendation_scripts(self):
        for filename, strategy in [('recommend_from_history','history'),
                                   ('recommend_from_interests','interests'),
                                   ('recommend_for_discovery','discovery')]:
            result=self.run_script('recommendations/'+filename+'.sh','Dragons')
            records=self.records(result.stdout)
            self.assertEqual(len(records),3)
            self.assertTrue(all(row['strategy']==strategy for row in records))

    def test_strategy_specific_reader_data(self):
        prompts = self.directory / 'prompts'
        prompts.mkdir()
        self.env['FAKE_PROMPTS'] = str(prompts)
        saved = dict(book(), status='finished', rating='5')
        self.db('add', value=saved)
        self.db('add', value=dict(book('Other', 'Other Writer'), genre='Mystery',
                                  status='reading', rating='2'))

        def contexts(interest):
            self.run_script('workflows/get_recommendations.sh', interest)
            return {strategy: json.loads((prompts / (strategy + '.txt')).read_text()
                                         .split('Reader data JSON:\n', 1)[1])
                    for strategy in ('history', 'interests', 'discovery')}

        data = contexts('dragons')
        history, interests, discovery = (data[s] for s in ('history', 'interests', 'discovery'))
        self.assertEqual(history['reading_history'][0]['rating'], '5')
        self.assertNotIn('session_interest', history)
        self.assertNotIn('fallback_preferences', history)
        self.assertEqual(set(interests), {'preferences', 'session_interest', 'existing_books'})
        self.assertEqual(interests['session_interest'], 'dragons')
        self.assertNotIn('reading_history', discovery)
        patterns = discovery['reading_patterns']
        self.assertEqual(patterns['saved_count'], 2)
        self.assertEqual(patterns['finished_count'], 1)
        self.assertEqual(patterns['highly_rated_finished_genres'], [{'value': 'Fantasy', 'count': 1}])
        self.assertEqual(patterns['genres'], [{'value': 'Fantasy', 'count': 1},
                                             {'value': 'Mystery', 'count': 1}])
        for context in data.values():
            self.assertEqual(context['existing_books'], [
                {'title': saved['title'], 'author': saved['author']},
                {'title': 'Other', 'author': 'Other Writer'}])
        changed = contexts('night')
        self.assertEqual(changed['history'], history)
        self.assertEqual(changed['interests']['session_interest'], 'night')
        self.assertEqual(changed['discovery']['session_interest'], 'night')

        self.env['BOOK_DB'] = str(self.directory / 'empty.csv')
        empty = contexts('')
        self.assertEqual(empty['history']['reading_history'], [])
        self.assertIn('The Lord of the Rings',
                      empty['history']['fallback_preferences'])
        self.assertEqual(empty['interests']['session_interest'], '')
        self.assertEqual(empty['discovery']['reading_patterns']['saved_count'], 0)
        self.assertEqual(empty['discovery']['reading_patterns']['genres'], [])

    def test_failure_and_authentication(self):
        for mode in ['fail','malformed']:
            self.env['FAKE_MODE']=mode
            result=self.run_script('workflows/get_recommendations.sh',check=False)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(result.stdout,'')
            if mode == 'fail':
                self.assertIn('ERROR: Simulated service unavailable', result.stderr)
        self.env['FAKE_AUTH']='Logged in using an API key'
        result=self.run_script('recommendations/recommend_from_history.sh',check=False)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('ChatGPT login',result.stderr)
    def assert_children_stopped(self):
        events=self.records(Path(self.env['FAKE_LOG']).read_text())
        for event in events:
            if 'pid' not in event:
                continue
            # Zombies are no longer running and will be reaped by their parent/init.
            status=subprocess.run(['ps','-o','stat=','-p',str(event['pid'])],capture_output=True,text=True).stdout.strip()
            self.assertTrue(not status or status.startswith('Z'), f"Process survived: {event} ({status})")
    def test_timeout(self):
        self.env.update(FAKE_MODE='hang',BOOK_AI_TIMEOUT='0.5')
        result=self.run_script('workflows/get_recommendations.sh',check=False)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('124',result.stderr)
        self.assert_children_stopped()
    def test_cancellation(self):
        self.env['FAKE_MODE']='hang'
        process=subprocess.Popen(['/bin/bash',str(ROOT/'workflows/get_recommendations.sh')],env=self.env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        try:
            deadline=time.monotonic()+5
            while time.monotonic()<deadline:
                log=Path(self.env['FAKE_LOG'])
                if log.exists() and log.read_text().count('"event": "child"')==3:
                    break
                time.sleep(.05)
            else:
                self.fail('Workers never started')
            process.terminate()
            process.communicate(timeout=5)
            self.assertEqual(process.returncode,143)
            self.assert_children_stopped()
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
    def test_path_with_spaces(self):
        copy=self.directory/'project with spaces'
        shutil.copytree(ROOT,copy,ignore=shutil.ignore_patterns('.git','__pycache__'))
        result=subprocess.run(['/bin/bash',str(copy/'data/book_database.sh'),'list'],env=self.env,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)

if __name__=='__main__':
    unittest.main(verbosity=2)
