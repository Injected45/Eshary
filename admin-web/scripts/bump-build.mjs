// Raises the build number in pubspec.yaml by one and prints "<build> <name>".
//
//   version: 1.0.7+7   ->   version: 1.0.8+8   prints   "8 1.0.8"
//
// build-apk.bat runs this before every build: Android refuses to install an
// APK whose build number (versionCode) is not higher than the installed one,
// and the app compares this number with the one published for an update.
import { readFileSync, writeFileSync } from 'node:fs';

const file = new URL('../../pubspec.yaml', import.meta.url);
const text = readFileSync(file, 'utf8');
const m = text.match(/^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$/m);
if (!m) {
  console.error('pubspec.yaml: no "version: x.y.z+n" line');
  process.exit(1);
}
const build = Number(m[4]) + 1;
const name = `${m[1]}.${m[2]}.${build}`;
writeFileSync(file, text.replace(m[0], `version: ${name}+${build}`));
console.log(`${build} ${name}`);
