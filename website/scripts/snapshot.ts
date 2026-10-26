import {writeFile} from 'node:fs/promises';
import {fetchStats} from '../src/github';
try {await writeFile(new URL('../public/github-stats.json',import.meta.url),JSON.stringify(await fetchStats(),null,2)+'\n');}
catch(error) {console.warn('GitHub snapshot unavailable; retaining previous verified snapshot.',String(error));}
