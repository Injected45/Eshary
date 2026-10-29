// A dry run of load93.mjs without any Supabase project: PGlite with every
// migration (like the tests), served on localhost over the Postgres protocol.
// One connection at a time, so it checks the script, not concurrency.
//
//   node load/local-server.mjs            (leave it running)
//   set LOAD_DB_URL=postgresql://postgres@localhost:55432/postgres
//   set LOAD_POOL=1 & node load/load93.mjs seed & node load/load93.mjs run
import { PGLiteSocketServer } from '@electric-sql/pglite-socket';
import { freshDb } from '../harness.mjs';

const db = await freshDb();
await db.exec(`create schema loadtest; create table loadtest.marker (made_at timestamptz default now());
               insert into loadtest.marker default values;`);
const server = new PGLiteSocketServer({ db, port: 55432, host: '127.0.0.1' });
await server.start();
console.log('PGlite with migrations 0001..0093 on postgresql://postgres@localhost:55432/postgres');
